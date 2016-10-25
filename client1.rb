load 'client.rb'
a = ClientChat.new(19999, nil, "aa", nil, 9999, 'localhost', 8002, lambda{ |obj|
  obj.register 0
  sleep 1
  obj.publish(1, 'ON', 'BB', 'CCC', 'DDD')
  sleep 1
  obj.inform_request 2
  sleep 7
  obj.bye_message("bb")
})
