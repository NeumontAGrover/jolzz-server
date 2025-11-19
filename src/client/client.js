let serverIP = "0.0.0.0";
let serverPort = 3333;

const websocket = new WebSocket(`ws://${serverIP}:${serverPort}`);

websocket.onopen = function(event) {
  console.info(`Opened WebSocket connection on ws://${serverIP}:${serverPort}`);
}

websocket.onmessage = function(event) {
    
}
