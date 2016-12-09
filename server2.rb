load 'server.rb'
addr = Socket.ip_address_list
server_ip = 'localhost' || addr.last.ip_address
port = 10000

puts "Server ip: #{server_ip} Port: #{port}"
server2 = ChatServer.new(server_ip, port)
server2.add_ui_address(server_ip, 8002);
server2.adjacent_servers.next_server(server_ip, 9999)
server2.adjacent_servers.previous_server(server_ip, 9999)
server2.start_server()
