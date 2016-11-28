load 'server.rb'

addr = Socket.ip_address_list
server_ip = addr.last.ip_address

server1 = ChatServer.new(server_ip, 9999)
server1.add_ui_address(server_ip, 8002);
server1.adjacent_servers.next_server(server_ip, 10000)
server1.adjacent_servers.previous_server(server_ip, 10000)
server1.start_server()
