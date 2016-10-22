var sys = require('sys'),
http = require('http');
http.createServer(function (req, res) {
    res.writeHead(200, {'Content-Type': 'text/event-stream'});
    var currentTime = new Date();
    sys.puts('Starting sending time');

      console.log(3333);
        res.write(
            "a"
        );

}).listen(8000)
