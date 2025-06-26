#!/usr/bin/env python3
"""
WebSocket Client Application for Envoy Proxy POC

This client application:
1. Creates 5 WebSocket connections from each client pod to Envoy proxy
2. Attempts 1 new connection per 10 seconds
3. Randomly sends messages over existing connections every 10-20 seconds
4. Logs responses (timestamp, server pod IP)
5. Provides HTTP health endpoint for Kubernetes health checks
"""

import asyncio
import websockets
import json
import random
import logging
import os
import signal
import sys
from datetime import datetime
from typing import List, Dict, Set
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import socket
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WebSocketClient:
    def __init__(self, client_id: str, envoy_endpoint: str):
        self.client_id = client_id
        self.envoy_endpoint = envoy_endpoint
        self.connections: List[websockets.WebSocketServerProtocol] = []
        self.max_connections = 5
        self.connection_interval = 10  # seconds
        self.message_interval_min = 10  # seconds
        self.message_interval_max = 20  # seconds
        self.running = False
        self.connection_tasks: Set[asyncio.Task] = set()
        self.message_tasks: Set[asyncio.Task] = set()
        
        # Get pod info
        self.pod_name = os.getenv('HOSTNAME', 'unknown-pod')
        self.pod_ip = self.get_pod_ip()
        
        logger.info(f"WebSocket Client initialized - ID: {self.client_id}, Pod: {self.pod_name}, IP: {self.pod_ip}")
        logger.info(f"Target Envoy endpoint: {self.envoy_endpoint}")
    
    def get_pod_ip(self) -> str:
        """Get the pod's IP address"""
        try:
            # Try to get IP from environment variable first (set by Kubernetes)
            if 'POD_IP' in os.environ:
                return os.environ['POD_IP']
            
            # Fallback to socket method
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
        except Exception as e:
            logger.warning(f"Could not determine pod IP: {e}")
            return "unknown"
    
    async def create_connection(self) -> bool:
        """Create a new WebSocket connection to Envoy"""
        if len(self.connections) >= self.max_connections:
            logger.debug(f"Max connections ({self.max_connections}) reached")
            return False
        
        connection_id = len(self.connections) + 1
        try:
            logger.info(f"Attempting to create connection #{connection_id} to {self.envoy_endpoint}")
            
            # Create WebSocket connection
            websocket = await websockets.connect(
                self.envoy_endpoint,
                ping_interval=30,
                ping_timeout=10,
                close_timeout=10
            )
            
            self.connections.append(websocket)
            logger.info(f"Successfully created connection #{connection_id} (Total: {len(self.connections)})")
            
            # Start message handling for this connection
            task = asyncio.create_task(self.handle_connection(websocket, connection_id))
            self.connection_tasks.add(task)
            task.add_done_callback(self.connection_tasks.discard)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to create connection #{connection_id}: {e}")
            return False
    
    async def handle_connection(self, websocket: websockets.WebSocketServerProtocol, connection_id: int):
        """Handle incoming messages for a specific connection"""
        try:
            logger.info(f"Starting message handler for connection #{connection_id}")
            
            async for message in websocket:
                try:
                    data = json.loads(message)
                    server_timestamp = data.get('timestamp', 'unknown')
                    server_pod_ip = data.get('pod_ip', 'unknown')
                    server_pod_name = data.get('pod_name', 'unknown')
                    
                    logger.info(f"[Conn #{connection_id}] Response from server pod {server_pod_name} ({server_pod_ip}): {server_timestamp}")
                    
                except json.JSONDecodeError:
                    logger.warning(f"[Conn #{connection_id}] Received non-JSON message: {message}")
                except Exception as e:
                    logger.error(f"[Conn #{connection_id}] Error processing message: {e}")
                    
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Connection #{connection_id} closed by server")
        except Exception as e:
            logger.error(f"Error in connection #{connection_id} handler: {e}")
        finally:
            # Remove from connections list
            if websocket in self.connections:
                self.connections.remove(websocket)
                logger.info(f"Removed connection #{connection_id} (Remaining: {len(self.connections)})")
    
    async def send_message(self, websocket: websockets.WebSocketServerProtocol, connection_id: int):
        """Send a message to the server through a specific connection"""
        try:
            message = {
                "client_id": self.client_id,
                "client_pod": self.pod_name,
                "client_ip": self.pod_ip,
                "timestamp": datetime.now().isoformat(),
                "message": f"Hello from client {self.client_id} via connection #{connection_id}",
                "connection_id": connection_id
            }
            
            await websocket.send(json.dumps(message))
            logger.info(f"[Conn #{connection_id}] Sent message to server")
            
        except websockets.exceptions.ConnectionClosed:
            logger.warning(f"[Conn #{connection_id}] Connection closed while sending message")
        except Exception as e:
            logger.error(f"[Conn #{connection_id}] Error sending message: {e}")
    
    async def connection_manager(self):
        """Manage WebSocket connections - create new ones every 10 seconds"""
        logger.info("Starting connection manager")
        
        while self.running:
            try:
                if len(self.connections) < self.max_connections:
                    await self.create_connection()
                
                await asyncio.sleep(self.connection_interval)
                
            except Exception as e:
                logger.error(f"Error in connection manager: {e}")
                await asyncio.sleep(5)  # Short delay before retrying
    
    async def message_sender(self):
        """Send random messages over existing connections"""
        logger.info("Starting message sender")
        
        while self.running:
            try:
                if self.connections:
                    # Pick a random connection
                    connection = random.choice(self.connections)
                    connection_id = self.connections.index(connection) + 1
                    
                    await self.send_message(connection, connection_id)
                
                # Wait random interval between messages
                interval = random.uniform(self.message_interval_min, self.message_interval_max)
                await asyncio.sleep(interval)
                
            except Exception as e:
                logger.error(f"Error in message sender: {e}")
                await asyncio.sleep(5)  # Short delay before retrying
    
    async def start(self):
        """Start the WebSocket client"""
        logger.info(f"Starting WebSocket client {self.client_id}")
        self.running = True
        
        # Start connection manager and message sender
        connection_task = asyncio.create_task(self.connection_manager())
        message_task = asyncio.create_task(self.message_sender())
        
        self.connection_tasks.add(connection_task)
        self.message_tasks.add(message_task)
        
        try:
            # Wait for both tasks
            await asyncio.gather(connection_task, message_task)
        except Exception as e:
            logger.error(f"Error in client main loop: {e}")
        finally:
            await self.stop()
    
    async def stop(self):
        """Stop the WebSocket client and close all connections"""
        logger.info(f"Stopping WebSocket client {self.client_id}")
        self.running = False
        
        # Close all WebSocket connections
        for websocket in self.connections.copy():
            try:
                await websocket.close()
            except Exception as e:
                logger.error(f"Error closing connection: {e}")
        
        # Cancel all tasks
        for task in self.connection_tasks.copy():
            task.cancel()
        
        for task in self.message_tasks.copy():
            task.cancel()
        
        # Wait for tasks to complete
        if self.connection_tasks:
            await asyncio.gather(*self.connection_tasks, return_exceptions=True)
        
        if self.message_tasks:
            await asyncio.gather(*self.message_tasks, return_exceptions=True)
        
        logger.info(f"WebSocket client {self.client_id} stopped")

class HealthCheckHandler(BaseHTTPRequestHandler):
    """HTTP handler for health checks"""
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                'status': 'healthy',
                'timestamp': datetime.now().isoformat(),
                'pod_name': os.getenv('HOSTNAME', 'unknown'),
                'service': 'websocket-client'
            }
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default HTTP server logging
        pass

def run_health_server(port: int = 8081):
    """Run HTTP health check server"""
    try:
        server = HTTPServer(('0.0.0.0', port), HealthCheckHandler)
        logger.info(f"Health check server started on port {port}")
        server.serve_forever()
    except Exception as e:
        logger.error(f"Health check server error: {e}")

async def main():
    """Main function"""
    # Configuration
    envoy_endpoint = os.getenv('ENVOY_ENDPOINT', 'ws://envoy-proxy-service.default.svc.cluster.local:80')
    client_id = os.getenv('CLIENT_ID', f"client-{os.getenv('HOSTNAME', 'unknown')}")
    health_port = int(os.getenv('HEALTH_PORT', '8081'))
    
    logger.info("=== WebSocket Client Application Starting ===")
    logger.info(f"Client ID: {client_id}")
    logger.info(f"Envoy Endpoint: {envoy_endpoint}")
    logger.info(f"Health Port: {health_port}")
    
    # Start health check server in a separate thread
    health_thread = threading.Thread(target=run_health_server, args=(health_port,), daemon=True)
    health_thread.start()
    
    # Create and start WebSocket client
    client = WebSocketClient(client_id, envoy_endpoint)
    
    # Handle shutdown signals
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, shutting down...")
        asyncio.create_task(client.stop())
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        await client.start()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt, shutting down...")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    finally:
        await client.stop()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Application interrupted by user")
    except Exception as e:
        logger.error(f"Application error: {e}")
        sys.exit(1)
