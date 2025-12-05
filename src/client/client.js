// let serverIP = "b16adab1-b381-42ef-becb-c0d6cde93283-jolzz.tysonjenkins.dev"
// let serverPort = "443"
let serverIP = "0.0.0.0";
let serverPort = "3333"

const websocket = new WebSocket(`ws://${serverIP}:${serverPort}`);

websocket.onopen = () => {
  console.info(`Opened WebSocket connection on ws://${serverIP}:${serverPort}`);
  websocket.send("tw");
  websocket.send("tw");
  // websocket.send("hello zig");
  // websocket.send("hello zig again");
  // websocket.send("What I'm doing?");
  // websocket.send("testing the inputs!");
}

websocket.onmessage = (event) => {
  console.log(event.data);
}
