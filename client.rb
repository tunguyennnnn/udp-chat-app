require 'socket'
s = UDPSocket.new
PORT = 1234
NAME = "AAA"
IP = Socket.ip_address_list.last.ip_address
HOST = 'localhost'

class ClientChat
  MAX_BYTE_SIZE = 140
  def initialize(port, ip, name, server_ip, server_port, func)
    @name = name
    @port = port
    @server_ip = server_ip
    @server_port = server_port
    @ip = ip || "127.0.0.1"
    @friends = {}
    @client = UDPSocket.new
    @client.bind('127.0.0.1', port)
    @request = nil
    @response = nil
    listen
    send(func)
    @request.join
    @response.join
  end

  def send(func)
    @request = Thread.new do
      func.call(self)
    end
  end

  def listen
    @response = Thread.new do
      loop{
        text, sender = @client.recvfrom(140)
        puts text
        handle_message(text, sender)
      }
    end
  end

  def handle_message(message, sender)
    partition = message.split(/\s+/)
    case partition[0]
    when "REGISTERED"
      @server_ip = sender[2]
      @server_port = sender[1]
    when "REGISTER-DENIED"
      register(partition[2], partition[3])
    when "PUBLISHED"
      puts message
    when "UNPUBLISHED"
      puts message
      publish(1, 'ON', 'BB', 'CCC', 'DDD')
    when "INFORMResp"
      name, port, status, *list_of_names = partition[2..-1]
      puts message
    when "FINDResp"
      rq, name, port, ip = partition[1..-1]
      @friends[name] = {port: port, ip: ip}
      puts message
    when "FINDDenied"
      name = partition.last
      @friends[name] = false
    when "REFER"
      ip, port = partition[2..-2]
      find_user(0, name, ip , port)
    when "CHAT"
      puts message
      name, ip , port, text = partition[1..-1]
      @friends[name] = {port: port, ip: ip}
    when "BYE"
      puts message
    else
    end
  end
  def register(rq ,server_ip = @server_ip, server_port = @server_port)
    message = "REGISTER #{rq} #{@name} #{@ip}"
    @client.send(message, 0, server_ip, server_port)
  end

  def find_user(rq,name, ip = @server_id, port = @server_port)
    message = "FINDReq #{rq} #{name}"
    @client.send(message, 0, ip, port)
  end

  def publish(rq, status, *list_of_names)
    message = "PUBLISH #{rq} #{@name} #{@port} #{status} #{list_of_names.join(' ')}"
    @client.send(message, 0, @server_ip, @server_port)
  end

  def inform_request(rq)
    message = "INFORMReq #{rq} #{@name}"
    @client.send(message, 0, @server_ip, @server_port)
  end

  def chat_message(name, text)
    puts @friends
    if @friends.has_key? name
      puts name
      if @friends[name]
        puts name
        port, ip  = @friends[name][:port], @friends[name][:ip]
        message = "CHAT #{@name} #{@ip} #{@port} "
        allowed_length = MAX_BYTE_SIZE -  message.bytesize
        while allowed_length < text.bytesize do
          @client.send(message + text[0...allowed_length], 0, ip, port)
          text = text[allowed_length..-1]
        end
        if text.bytesize > 0
          @client.send(message + text, 0, ip, port)
        end
      else
        puts "#{name} doesn't wanna talk to you"
      end
    else
      puts "#{name} is not in the list of your friend"
    end
  end

  def bye_message(name)
    if @friends.has_key? name
      puts @friends
      if @friends[name]
        port, ip  = @friends[name][:port], @friends[name][:ip]
        @client.send("BYE #{@name} #{@ip} #{@port}", 0, ip, port)
      else
        puts "#{name} doesn't wanna talk to you"
      end
    else
      puts "#{name} is not in the list of your friend"
    end
  end
end
