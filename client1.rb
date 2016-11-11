load 'client.rb'
addr = Socket.ip_address_list
server_ip = 'localhost' || addr.last.ip_address
a = ClientChat.new(19999, server_ip , "aa", server_ip, 9999, 'localhost', 8002, lambda{ |obj|
  obj.register
  sleep 1
  obj.publish('ON', 'BB', 'CCC', 'DDD')
  obj.inform_request
  sleep 10
  obj.bye_message("bb")
})
