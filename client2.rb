load 'client.rb'
addr = Socket.ip_address_list
server_ip = addr.last.ip_address
b = ClientChat.new(20000, server_ip, "bb", server_ip, 9999,'localhost', 8002, lambda{ |obj|

})
