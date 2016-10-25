var sys = require('sys'),
http = require('http');
var fs = require('fs')

const dgram = require('dgram');
const server = dgram.createSocket('udp4');
server.bind(8002);

var messageToUi = {};

http.createServer(function (req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.writeHead(200, {'Content-Type': 'text/html'});
    var currentTime = new Date();
    sys.puts('Starting sending time');
    setInterval(function(){
      if (Object.size(messageToUi) != 0){
        res.write(JSON.stringify(messageToUi));
        messageToUi = {};
      }
    }, 100);

}).listen(8000)

server.on('error', function(err){
  console.log(`server error:\n${err.stack}`);
  server.close();
});

server.on('message', function(msg, rinfo){
  var counter = 1;
  while (messageToUi['data' + counter]){
    counter++;
  }
  messageToUi['data' + counter] = JSON.parse(msg);
});
server.on('listening', function(){
  var address = server.address();
  console.log(`server listening ${address.address}:${address.port}`);
});
var message = `REGISTER 0 XX ${1123123}`


String.prototype.isEmpty = function(){
  return this === ''
}

Object.size = function(obj) {
    var size = 0, key;
    for (key in obj) {
        if (obj.hasOwnProperty(key)) size++;
    }
    return size;
};
