load 'client.rb'
b = ClientChat.new(20000, nil, "bb", nil, 9999, 'localhost', 8002, lambda{ |obj|
  obj.register 0
  sleep 1
  obj.find_user 1, "aa"
  sleep(5)
  obj.chat_message("aa", "hello how are you bae")
})
