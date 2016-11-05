load 'client.rb'
b = ClientChat.new(20003, nil, "ee", nil, 9999,'localhost', 8002, lambda{ |obj|
  obj.register 0
})
