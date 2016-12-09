load 'client.rb'
addr = Socket.ip_address_list
server_ip = addr.last.ip_address
port = ARGV[1] || Random.new.rand(2000..65535)
name = ARGV[0] || "ff"
f = ClientChat.new(name, port, server_ip,'172.31.54.60', 8002, lambda{ |obj|
  #testing
})
