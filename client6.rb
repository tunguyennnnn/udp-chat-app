load 'client.rb'
b = ClientChat.new(20004, nil, "ff", nil, 9999,'localhost', 8002, lambda{ |obj|
  obj.register 0
})
