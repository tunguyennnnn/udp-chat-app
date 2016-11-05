require 'thread'
require 'json'
require 'socket'

class ClientChat
  MAX_BYTE_SIZE = 140
  def initialize(port, ip, name, server_ip, server_port, ui_ip, ui_port, func = lambda{|obj|})
    @name = name
    @port = port
    @ui_ip = ui_ip
    @ui_port = ui_port
    @server_ip = server_ip
    @server_port = server_port
    @ip = ip || "127.0.0.1"
    @friends = {}
    @rq = 0;
    @resource_semaphore = Mutex.new
    @client = UDPSocket.new
    @client.bind(ip, port)
    @request = nil
    @response = nil
    listen
    request(func)
    @request.join
    @response.join
  end

  def request(func)
    @request = Thread.new do
      func.call(self)
    end
  end

  def listen
    send_to_ui("Client #{@name} start", "")
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
    message_type = partition[0]
    if message_type.upcase == "EXEC" #exec is used to execute commands from the ui
      func_name, *params = partition[1..-1]
      send(func_name, *params)
    else
      send_to_ui("Received", message)
      case partition[0]
      when "REGISTERED"
        @server_ip = sender[2]
        @server_port = sender[1]
      when "REGISTER-DENIED"
        # Do nothing
      when "PUBLISHED"
        @token = partition.last()
      when "UNPUBLISHED"
      when "INFORMResp"
      when "INFORM-REQ-DENIED"
      when "FINDResp"
        access_resource(lambda {|rq, friends|
          rq, name, port, ip, token = partition[1..-1]
          friends[name] = {port: port, ip: ip, token: token}
        })
      when "FINDDenied"
      when "REFER"
        rq, name, server_ip, server_port = partition[1..-1]
        #find_user(name, server_ip, server_port)

      when "CHAT"
        handle_chat(message, sender)
      else
      end
    end
  end

  def handle_chat(message, sender)
    token, name, ip, port, text =  message.split(/\s+/)[1..-1]
    unless token == @token
      @client.send("Error: You cannot talk to me")
    end
  end

  def register(server_ip = @server_ip, server_port = @server_port)
    access_resource(lambda { |rq, friends|
      message = "REGISTER #{rq} #{@name} #{@ip}"
      puts message, server_ip, server_port
      @client.send(message, 0, server_ip, server_port)
    })
  end

  def find_user(name, ip = @server_id, port = @server_port)
    access_resource( lambda { |rq, friends|
      message = "FINDReq #{rq} #{name} #{@name}"
      @client.send(message, 0, ip, port)
    })
  end

  def publish(status, *list_of_names)
    access_resource( lambda { |rq, friends|
      message = "PUBLISH #{rq} #{@name} #{@port} #{status} #{list_of_names.join(' ')}"
      @client.send(message, 0, @server_ip, @server_port)
    })
  end

  def inform_request()
    access_resource( lambda { |rq, friends|
      message = "INFORMReq #{rq} #{@name}"
      @client.send(message, 0, @server_ip, @server_port)
    })
  end

  def chat_message(name, text)
    access_resource( lambda { |rq, friends|
      puts friends
      if friends.has_key? name
        if friends[name]
          port, ip, token = friends[name][:port], friends[name][:ip], friends[name][:token]
          message = "CHAT #{token} #{@name} #{@ip} #{@port} "
          allowed_length = MAX_BYTE_SIZE - message.bytesize
          while allowed_length < text.bytesize do
            @client.send(message + text[0..allowed_length], 0, ip, port)
            text = text[allowed_length..-1]
          end
          if text.bytesize > 0
            @client.send(message + text, 0, ip, port)
          end
        else
          send_to_ui("Error", "#{name} doesn't wanna talk to you")
        end
      else
        send_to_ui("Error", "#{name} is not in the list of your friends")
      end
    })
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

  def access_resource(func)
    @resource_semaphore.synchronize{
      func.call(@rq, @friends)
      @rq += 1
    }
  end

  def send_to_ui(type, message)
    @client.send({type: "client", message: "#{Time.new.inspect} #{type} #{message}", sender: "#{@name}-#{@port}", ip: @ip}.to_json, 0 , @ui_ip, @ui_port)
  end
end
