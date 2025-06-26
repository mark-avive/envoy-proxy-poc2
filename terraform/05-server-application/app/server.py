#!/usr/bin/env python3
"""
WebSocket Server Application for Envoy Proxy POC

This is a minimalist WebSocket server that:
1. Opens and holds WebSocket connections from clients
2. Waits for messages over the WebSocket pipe
3. Responds with current timestamp and pod's IP address
4. Provides HTTP health endpoint for Kubernetes health checks
"""

import asyncio
import websockets
import json
import socket
import os
import logging
from datetime import datetime
from typing import Set
import signal
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class HealthCheckHandler(BaseHTTPRequestHandler):
    """HTTP handler for health check endpoint"""
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            health_data = {
                'status': 'healthy',
                'timestamp': datetime.utcnow().isoformat(),
                'pod_ip': os.getenv('POD_IP', 'unknown'),
                'pod_name': os.getenv('HOSTNAME', 'unknown')
            }
            self.wfile.write(json.dumps(health_data).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default HTTP server logging to reduce noise
        pass

class WebSocketServer:
    def __init__(self, host: str = "0.0.0.0", port: int = 8080):
        self.host = host
        self.port = port
        self.connected_clients: Set[websockets.WebSocketServerProtocol] = set()
        self.pod_ip = self._get_pod_ip()
        self.pod_name = os.getenv('HOSTNAME', 'unknown-pod')
        self.health_server = None
        
    def _get_pod_ip(self) -> str:
        """Get the pod's IP address"""
        try:
            # Try to get IP from environment variable (Kubernetes sets this)
            pod_ip = os.getenv('POD_IP')
            if pod_ip:
                return pod_ip
            
            # Fallback: get IP by connecting to a remote address
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
        except Exception as e:
            logger.warning(f"Could not determine pod IP: {e}")
            return "unknown"
    
    def start_health_server(self):
        """Start HTTP health check server on port 8081"""
        def run_health_server():
            try:
                self.health_server = HTTPServer((self.host, 8081), HealthCheckHandler)
                logger.info(f"Health check server started on http://{self.host}:8081/health")
                self.health_server.serve_forever()
            except Exception as e:
                logger.error(f"Health server error: {e}")
        
        # Run health server in a separate thread
        health_thread = threading.Thread(target=run_health_server, daemon=True)
        health_thread.start()
        return health_thread
    
    async def register(self, websocket: websockets.WebSocketServerProtocol) -> None:
        """Register a new client connection"""
        self.connected_clients.add(websocket)
        client_info = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
        logger.info(f"Client connected: {client_info}. Total clients: {len(self.connected_clients)}")
    
    async def unregister(self, websocket: websockets.WebSocketServerProtocol) -> None:
        """Unregister a client connection"""
        self.connected_clients.discard(websocket)
        client_info = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
        logger.info(f"Client disconnected: {client_info}. Total clients: {len(self.connected_clients)}")
    
    async def handle_message(self, websocket: websockets.WebSocketServerProtocol, message: str) -> None:
        """Handle incoming message from client"""
        try:
            # Parse incoming message
            data = json.loads(message) if message.startswith('{') else {"message": message}
            
            # Create response with timestamp and pod info
            response = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "pod_ip": self.pod_ip,
                "pod_name": self.pod_name,
                "received_message": data,
                "server_info": {
                    "version": "1.0.0",
                    "type": "websocket-server"
                }
            }
            
            # Send response back to client
            await websocket.send(json.dumps(response))
            
            client_info = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
            logger.info(f"Processed message from {client_info}: {data}")
            
        except json.JSONDecodeError:
            # Handle non-JSON messages
            response = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "pod_ip": self.pod_ip,
                "pod_name": self.pod_name,
                "received_message": message,
                "error": "Invalid JSON format"
            }
            await websocket.send(json.dumps(response))
        except Exception as e:
            logger.error(f"Error handling message: {e}")
            error_response = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "pod_ip": self.pod_ip,
                "pod_name": self.pod_name,
                "error": str(e)
            }
            await websocket.send(json.dumps(error_response))
    
    async def client_handler(self, websocket: websockets.WebSocketServerProtocol, path: str) -> None:
        """Handle individual client connections"""
        await self.register(websocket)
        try:
            async for message in websocket:
                await self.handle_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Client connection closed normally")
        except Exception as e:
            logger.error(f"Error in client handler: {e}")
        finally:
            await self.unregister(websocket)
    
    async def health_check_handler(self, websocket: websockets.WebSocketServerProtocol, path: str) -> None:
        """Handle health check requests"""
        health_status = {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "pod_ip": self.pod_ip,
            "pod_name": self.pod_name,
            "connected_clients": len(self.connected_clients),
            "uptime": "N/A"  # Could implement uptime tracking
        }
        await websocket.send(json.dumps(health_status))
        await websocket.close()
    
    async def start_server(self) -> None:
        """Start the WebSocket server"""
        logger.info(f"Starting WebSocket server on {self.host}:{self.port}")
        logger.info(f"Pod IP: {self.pod_ip}, Pod Name: {self.pod_name}")
        
        # Create server with different handlers for different paths
        async def router(websocket, path):
            if path == "/health":
                await self.health_check_handler(websocket, path)
            else:
                await self.client_handler(websocket, path)
        
        # Start the server
        server = await websockets.serve(
            router,
            self.host,
            self.port,
            ping_interval=30,  # Send ping every 30 seconds
            ping_timeout=10,   # Wait 10 seconds for pong
            max_size=1024*1024,  # Max message size 1MB
            max_queue=32       # Max queued messages
        )
        
        logger.info(f"WebSocket server started successfully on ws://{self.host}:{self.port}")
        return server

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    logger.info(f"Received signal {signum}, shutting down gracefully...")
    sys.exit(0)

async def main():
    """Main application entry point"""
    # Setup signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Get configuration from environment variables
    host = os.getenv('SERVER_HOST', '0.0.0.0')
    port = int(os.getenv('SERVER_PORT', '8080'))
    
    # Create and start server
    server_instance = WebSocketServer(host, port)
    
    # Start health check server
    health_thread = server_instance.start_health_server()
    
    # Start WebSocket server
    server = await server_instance.start_server()
    
    try:
        # Keep server running
        await server.wait_closed()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt, shutting down...")
    except Exception as e:
        logger.error(f"Server error: {e}")
    finally:
        # Shutdown health server
        if server_instance.health_server:
            server_instance.health_server.shutdown()
        logger.info("Server shutdown complete")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Application interrupted by user")
    except Exception as e:
        logger.error(f"Application error: {e}")
        sys.exit(1)
