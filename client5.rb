load 'client.rb'
addr = Socket.ip_address_list
server_ip = 'localhost' || addr.last.ip_address
port = ARGV[1] || Random.new.rand(2000..65535)
name = ARGV[0] || "ee"
e = ClientChat.new(name, port, server_ip,'localhost', 8002, lambda{ |obj|

})
