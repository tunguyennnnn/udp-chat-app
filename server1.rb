load 'server.rb'

addr = Socket.ip_address_list
server_ip = addr.last.ip_address

port = 9999
puts "Server ip: #{server_ip} Port: #{port}"
server1 = ChatServer.new(server_ip, port)
server1.add_ui_address("172.31.54.60", 8002);
server1.adjacent_servers.next_server(server_ip, 10000)
server1.adjacent_servers.previous_server(server_ip, 10000)
server1.start_server()
