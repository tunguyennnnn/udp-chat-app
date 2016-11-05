load 'client.rb'
addr = Socket.ip_address_list
server_ip = 'localhost' || addr.last.ip_address
b = ClientChat.new(20000, server_ip, "bb", server_ip, 9999,'localhost', 8002, lambda{ |obj|
  obj.register
  obj.find_user "aa"
  sleep(5)
  obj.chat_message("aa", "hello how are you bae")
})
