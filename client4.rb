load 'client.rb'
b = ClientChat.new(20002, nil, "dd", nil, 9999,'localhost', 8002, lambda{ |obj|
  obj.register 0
})
