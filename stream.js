var sys = require('sys'),
http = require('http');
var fs = require('fs')
var qs = require('querystring');

const dgram = require('dgram');
const server = dgram.createSocket('udp4');

/// udp server /////
server.bind(8002, "172.31.54.60");

var messageToUi = {};


//////http server//////
http.createServer(function (req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.writeHead(200, {'Content-Type': 'text/html'});
  res.connection.setTimeout(0);
  if (req.method === 'GET'){
    var currentTime = new Date();
    sys.puts('Starting sending time');
    setInterval(function(){
      if (Object.size(messageToUi) != 0){
        res.write(JSON.stringify(messageToUi));
        messageToUi = {};
      }
    }, 100);
  }
  else if (req.method === 'POST'){
    var body = ''
    req.on('data', function(data){
      body += data;
    });

    req.on('end', function () {
      sendTo(qs.parse(body));
      console.log(3333);

    });
    res.end();
  }

}).listen(8000, '172.31.54.60')


function sendTo(data){
  console.log(data)
  var port = data.port;
  var ip = data.ip;
  var message = 'EXEC ' + data.message;
  console.log(ip);
  console.log(port);
  server.send(message, 0, message.length, port, ip);
}

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
