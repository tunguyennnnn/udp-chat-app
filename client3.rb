load 'client.rb'
b = ClientChat.new(20001, nil, "cc", nil, 9999,'localhost', 8002, lambda{ |obj|
  obj.register 0
})
