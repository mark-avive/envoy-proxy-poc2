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
        self.max_connections = int(os.getenv('MAX_CONNECTIONS', '5'))
        self.connection_interval = int(os.getenv('CONNECTION_INTERVAL', '10'))  # seconds
        self.message_interval_min = int(os.getenv('MESSAGE_INTERVAL_MIN', '10'))  # seconds
        self.message_interval_max = int(os.getenv('MESSAGE_INTERVAL_MAX', '20'))  # seconds
        self.running = False
        self.connection_tasks: Set[asyncio.Task] = set()
        self.message_tasks: Set[asyncio.Task] = set()
        
        # Get pod info
        self.pod_name = os.getenv('HOSTNAME', 'unknown-pod')
        self.pod_ip = self.get_pod_ip()
        
        logger.info(f"Client {self.client_id} initialized:")
        logger.info(f"  Max connections: {self.max_connections}")
        logger.info(f"  Connection interval: {self.connection_interval}s")
        logger.info(f"  Message interval: {self.message_interval_min}-{self.message_interval_max}s")
        logger.info(f"  Pod: {self.pod_name} ({self.pod_ip})")

    def get_pod_ip(self) -> str:
        """Get the pod's IP address"""
        try:
            return os.getenv('POD_IP', socket.gethostbyname(socket.gethostname()))
        except Exception as e:
            logger.warning(f"Could not determine pod IP: {e}")
            return 'unknown'

    async def create_connection(self, connection_id: int) -> bool:
        """Create a single WebSocket connection"""
        try:
            logger.info(f"Attempting to create connection #{connection_id} to {self.envoy_endpoint}")
            
            headers = {
                'X-Client-ID': self.client_id,
                'X-Pod-Name': self.pod_name,
                'X-Pod-IP': self.pod_ip,
                'X-Connection-ID': str(connection_id)
            }
            
            websocket = await websockets.connect(
                self.envoy_endpoint,
                extra_headers=headers,
                ping_interval=30,
                ping_timeout=10,
                close_timeout=10
            )
            
            self.connections.append(websocket)
            logger.info(f"Successfully created connection #{connection_id}. Total: {len(self.connections)}")
            
            # Start message handler for this connection
            message_task = asyncio.create_task(
                self.handle_messages(websocket, connection_id)
            )
            self.message_tasks.add(message_task)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to create connection #{connection_id}: {e}")
            return False

    async def handle_messages(self, websocket, connection_id: int):
        """Handle sending and receiving messages for a connection"""
        try:
            # Send initial message
            await self.send_message(websocket, connection_id)
            
            while self.running and not websocket.closed:
                try:
                    # Wait for message from server or timeout
                    message = await asyncio.wait_for(
                        websocket.recv(), 
                        timeout=5.0
                    )
                    
                    # Parse and log the response
                    try:
                        data = json.loads(message)
                        server_pod_ip = data.get('server_pod_ip', 'unknown')
                        timestamp = data.get('timestamp', 'unknown')
                        logger.info(f"Response from server {server_pod_ip} at {timestamp} (connection #{connection_id})")
                    except json.JSONDecodeError:
                        logger.info(f"Non-JSON response on connection #{connection_id}: {message}")
                    
                    # Schedule next message after random interval
                    await asyncio.sleep(random.randint(self.message_interval_min, self.message_interval_max))
                    await self.send_message(websocket, connection_id)
                    
                except asyncio.TimeoutError:
                    # No message received, send a ping/message
                    await self.send_message(websocket, connection_id)
                    await asyncio.sleep(1)
                    
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Connection #{connection_id} closed by server")
        except Exception as e:
            logger.error(f"Error handling messages for connection #{connection_id}: {e}")
        finally:
            # Remove from connections list
            if websocket in self.connections:
                self.connections.remove(websocket)
                logger.info(f"Connection #{connection_id} removed. Total: {len(self.connections)}")

    async def send_message(self, websocket, connection_id: int):
        """Send a message to the server"""
        try:
            message = {
                "type": "ping",
                "client_id": self.client_id,
                "pod_name": self.pod_name,
                "pod_ip": self.pod_ip,
                "connection_id": connection_id,
                "timestamp": datetime.now().isoformat(),
                "message": f"Hello from {self.client_id} connection #{connection_id}"
            }
            
            await websocket.send(json.dumps(message))
            logger.debug(f"Sent message from connection #{connection_id}")
            
        except Exception as e:
            logger.error(f"Failed to send message on connection #{connection_id}: {e}")

    async def connection_manager(self):
        """Manage connection creation at specified intervals"""
        connection_count = 0
        
        while self.running:
            try:
                current_connections = len(self.connections)
                
                if current_connections < self.max_connections:
                    connection_count += 1
                    success = await self.create_connection(connection_count)
                    
                    if success:
                        logger.info(f"Total active connections: {len(self.connections)}")
                    
                    # Wait before attempting next connection
                    await asyncio.sleep(self.connection_interval)
                else:
                    # All connections established, wait longer
                    await asyncio.sleep(30)
                    
            except Exception as e:
                logger.error(f"Error in connection manager: {e}")
                await asyncio.sleep(5)

    async def start(self):
        """Start the WebSocket client"""
        logger.info(f"Starting WebSocket client {self.client_id}")
        logger.info(f"Target endpoint: {self.envoy_endpoint}")
        logger.info(f"Will attempt {self.max_connections} connections")
        
        self.running = True
        
        # Start connection manager
        connection_task = asyncio.create_task(self.connection_manager())
        self.connection_tasks.add(connection_task)
        
        try:
            # Run until stopped
            while self.running:
                await asyncio.sleep(1)
                
                # Log status periodically
                if len(self.connections) > 0:
                    logger.info(f"Status: {len(self.connections)} active connections")
                    
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
        finally:
            await self.stop()

    async def stop(self):
        """Stop the WebSocket client"""
        logger.info("Stopping WebSocket client...")
        self.running = False
        
        # Cancel all tasks
        for task in self.connection_tasks:
            task.cancel()
        for task in self.message_tasks:
            task.cancel()
            
        # Close all connections
        close_tasks = []
        for websocket in self.connections[:]:  # Create a copy to avoid modification during iteration
            close_tasks.append(websocket.close())
            
        if close_tasks:
            await asyncio.gather(*close_tasks, return_exceptions=True)
            
        self.connections.clear()
        logger.info("WebSocket client stopped")

class HealthHandler(BaseHTTPRequestHandler):
    """HTTP health check handler"""
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            status = {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "client_id": os.getenv('CLIENT_ID', 'unknown'),
                "pod_name": os.getenv('HOSTNAME', 'unknown'),
                "pod_ip": os.getenv('POD_IP', 'unknown')
            }
            
            self.wfile.write(json.dumps(status).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default HTTP logging
        pass

def start_health_server(port: int):
    """Start HTTP health check server"""
    server = HTTPServer(('0.0.0.0', port), HealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    logger.info(f"Health check server started on port {port}")
    return server

async def main():
    """Main application entry point"""
    # Configuration from environment variables
    envoy_endpoint = os.getenv('ENVOY_ENDPOINT', 'ws://envoy-proxy-service.default.svc.cluster.local:80')
    client_id = os.getenv('CLIENT_ID', f'client-{random.randint(1000, 9999)}')
    health_port = int(os.getenv('HEALTH_PORT', '8081'))
    
    # Start health check server
    health_server = start_health_server(health_port)
    
    # Create and start WebSocket client
    client = WebSocketClient(client_id, envoy_endpoint)
    
    # Handle shutdown signals
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}")
        client.running = False
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        await client.start()
    except Exception as e:
        logger.error(f"Application error: {e}")
    finally:
        health_server.shutdown()
        logger.info("Application shutdown complete")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Application interrupted")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)
