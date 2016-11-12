require 'thread'
require 'json'
require 'socket'

class ClientChat
  MAX_BYTE_SIZE = 140

  TIMES_REPEATED = 2;

  REQUEST_TABLE = {"REGISTER" => ["REGISTERED", "REGISTER-DEINIED"],
                   "PUBLISH" => ["PUBLISHED", "UNPUBLISHED"],
                   "INFORMReq" => ["INFORMResp"],
                   "FINDReq" => ["FINDResp", "FINDDenied", "REFER"],
                   "CHAT" => [],
                   "BYE" => []
                  }

  EXEC_TABLE = ["register", "find_user", "publish", "inform_request", "chat_message", "bye_message"]

  HANDLE_REQUEST_TABLE = ["handle_registered", "handle_register_denied", "handle_published", "handle_unpublished", "handle_findresp",
                          "handle_finddenied", "handle_refer", "handle_informresp", "handle_informdenied", "handle_chat_denied", "handle_chat", "handle_bye"]

  def initialize(port, ip, name, server_ip, server_port, ui_ip, ui_port, func = lambda{|obj|})
    #initialize client params
    @name = name
    @port = port
    @ip = ip || "127.0.0.1"

    #initialize server attrs
    @server_ip = server_ip
    @server_port = server_port

    #intialize ui monitor server attrs
    @ui_ip = ui_ip
    @ui_port = ui_port

    #internal data structures for handling message
    @resource_semaphore = Mutex.new
    @rq = 0;
    @friends = {}
    @request_table = {}

    #intialize socket
    @client = UDPSocket.new
    @client.bind(ip, port)

    #start the client udp server
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

  #init server listening
  def listen
    send_to_ui("Client #{@name} start", "")
    @response = Thread.new do
      loop{
        text, sender = @client.recvfrom(1000)
        handle_message(text, sender)
      }
    end
  end

  # handle message sent from other sockets:
  def handle_message(message, sender)
    partition = message.split(/\s+/) #parsing the message
    puts message
    message_type = partition[0]
    if message_type.upcase == "EXEC" #exec is used to execute commands from the ui
      func_name, *params = partition[1..-1]
      if EXEC_TABLE.include? func_name
        Thread.new{
           send(func_name, *params)
         }.run
      end
    else
      func_name = partition[0].downcase.sub('-', '_')
      if HANDLE_REQUEST_TABLE.include? "handle_#{func_name}"
        Thread.new {
          send("handle_#{func_name}",message, sender)
        }.join
      end
    end
  end

  #################### REGISTER USER ###########################

  def register(server_ip = @server_ip, server_port = @server_port)
    rq_num = nil;
    message = ""
    access_resource do |rq, friends, request_table|
      rq_num = rq.to_s
      message = "REGISTER #{rq} #{@name} #{@ip}"
      #before sending register message, push the procedure
      request_table["REGISTER"] = request_table["REGISTER"] || {}
      request_table["REGISTER"][rq.to_s] = lambda{
        @client.send(message, 0, server_ip, server_port)
      }
      @client.send(message, 0, server_ip, server_port)
      @rq += 1
    end
    TIMES_REPEATED.times do
      sleep(1)
      access_resource { |rq, friends, request_table|
        if request_table["REGISTER"][rq_num]
          send_to_ui("Re Attempt", message)
          request_table["REGISTER"][rq_num.to_s].call
        else
          break
        end
      }
    end
  end

  def handle_registered(message, sender)
    rq_num = message.split(/\s+/)[1]
    ip ,port = sender[2], sender[1]
    access_resource{|rq, friends, request_table|
      #if rq corresponds to what stored into requestable -> registered and clean the register table
      if (request_table["REGISTER"] && request_table["REGISTER"][rq_num])
        @server_port = ip
        @server_port = port
        request_table["REGISTER"].delete rq_num
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_register_denied(message, sender)
    rq_num, next_server_ip, next_port = message.split(/\s+/)[1..-1]
    correct_rq = nil
    access_resource{|rq, friends, request_table|
      if (request_table["REGISTER"] && request_table["REGISTER"][rq_num])
        request_table["REGISTER"].delete rq_num
        correct_rq = true
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }

    if correct_rq
      Thread.new {
        register(next_server_ip, next_server_port)
      }
    end
  end


  #################### PUBLISH ###############

  def publish(status, *list_of_names)
    rq_num = "0"
    message = ""
    access_resource{|rq, friends, request_table|
      rq_num = rq.to_s
      message = "PUBLISH #{rq} #{@name} #{@port} #{status} #{list_of_names.join(' ')}"
      request_table["PUBLISH"] = request_table["PUBLISH"] || {}
      request_table["PUBLISH"][rq_num] = lambda{
        @client.send(message, 0, @server_ip, @server_port)
      }
      @client.send(message, 0, @server_ip, @server_port)
      @rq += 1
    }

    TIMES_REPEATED.times do
      sleep(1)
      access_resource { |rq, friends, request_table|
        if request_table["PUBLISH"][rq_num]
          send_to_ui("Re Attempt", message)
          request_table["PUBLISH"][rq_num].call
        else
          break
        end
      }
    end
  end

  def handle_published(message, sender)
    rq_num = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["PUBLISH"] && request_table["PUBLISH"][rq_num]
        request_table["PUBLISH"].delete rq_num
        send_to_ui("Received", message)
        @token = message.split(/\s+/).last()
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_unpublished(message, sender)
    rq_num = message.split(/\s+/)[1]
    access_resource {|rq, friends, request_table|
      if request_table["PUBLISH"] && request_table["PUBLISH"][rq_num]
        request_table["REGISTER"].delete rq_num
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end


  ##################### REQUEST INFORMATION ###############
  def inform_request
    rq_num = "0"
    message = ""
    access_resource{ |rq, friends, request_table|
      rq_num = rq.to_s
      message = "INFORMReq #{rq} #{@name}"
      request_table["INFORM"] = request_table["INFORM"] || {}
      request_table["INFORM"][rq_num] = lambda{
        @client.send(message, 0, @server_ip, @server_port)
      }
      @client.send(message, 0, @server_ip, @server_port)
      @rq += 1
    }

    TIMES_REPEATED.times do
      sleep(1)
      access_resource { |rq, friends, request_table|
        if request_table["INFORM"][rq_num]
          send_to_ui("Re Attempt", message)
          request_table["INFORM"][rq_num].call
        else
          break
        end
      }
    end
  end

  def handle_informresp(message, sender)
    rq_num = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["INFORM"] && request_table["INFORM"][rq_num]
        request_table["INFORM"].delete rq_num
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_informdenied(message, sender)
    rq_num = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["INFORM"] && request_table["INFORM"][rq_num]
        request_table["INFORM"].delete rq_num
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end


  ###################### FIND USER #########################
  def find_user(name, ip = @server_id, port = @server_port)
    rq_num = "0"
    message = ""
    access_resource{ |rq, friends, request_table|
      rq_num = rq.to_s
      message = "FINDReq #{rq} #{name} #{@name}"
      request_table["FIND"] = request_table["FIND"] || {}
      request_table["FIND"][rq_num] = lambda {
        @client.send(message, 0, ip, port)
      }
      @client.send(message, 0, ip, port)
      @rq += 1
    }

    TIMES_REPEATED.times do
      sleep(1)
      access_resource { |rq, friends, request_table|
        if request_table["FIND"][rq_num]
          send_to_ui("Re Attempt", message)
          request_table["FIND"][rq_num].call
        else
          break
        end
      }
    end
  end

  def handle_findresp(message, sender)
    rq_num, name, port, ip, token  = message.split(/\s+/)[1..-1]
    access_resource do |rq, friends, request_table|
      if request_table["FIND"] && request_table["FIND"][rq_num]
        request_table["FIND"].delete  rq_num
        friends[name] = {port: port, ip: ip, token: token}
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    end
  end

  def handle_finddenied(message, sender)
    rq_num = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["FIND"] && request_table["FIND"][rq_num]
        request_table["FIND"].delete rq_num
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_refer(message, sender)
    rq_num, ip, port = message.split(/\s+/)[1..-1]
    access_resource{|rq, friends, request_table|
      if request_table["FIND"] && request_table["FIND"][rq_num]
        request_table["FIND"].delete rq_num
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  ##################### CHAT #########################
  def chat_message(name, *text)
    text = text.join(' ')
    access_resource{ |rq, friends, request_table|
      if friends.has_key? name
        if friends[name]
          port, ip, token = friends[name][:port], friends[name][:ip], friends[name][:token]
          signature = rand(1000).to_s
          if token
            message = "CHAT #{token} #{@name} #{@ip} #{@port} #{signature}"
          else
            message = "CHAT #{@name} #{@ip} #{@port} #{signature}"
          end
          allowed_length = MAX_BYTE_SIZE - message.bytesize - 3
          while allowed_length < text.bytesize do
            @client.send("#{message} 1 #{text[0..allowed_length]}", 0, ip, port)
            text = text[allowed_length..-1]
          end
          if text.bytesize > 0
            @client.send("#{message} 0 #{text}", 0, ip, port)
          end
        else
          send_to_ui("Error", "#{name} doesn't wanna talk to you")
        end
      else
        send_to_ui("Error", "#{name} is not in the list of your friends")
      end
    }
  end

  def handle_chat(message, sender)
    token, name, ip, port, signature, more, *text =  message.split(/\s+/)[1..-1]
    text = text.join(' ')
    if @token && token != @token
      @client.send("CHAT-DENIED You cannot talk to me", 0, sender[2], sender[1])
    else
      access_resource{|rq, friends, request_table|
        friends[name] = {port: port, ip: ip}
        request_table["CHAT"] = request_table["CHAT"] || {}
        request_table["CHAT"][signature.to_s] = request_table["CHAT"][signature.to_s] || ""
        puts request_table["CHAT"]
        if more.to_s == "1"
          request_table["CHAT"][signature.to_s] += text
        else
          final_message = "CHAT message from #{name} #{request_table["CHAT"][signature.to_s] + text}"
          send_to_ui("Received", final_message)
        end
      }
    end
  end

  def handle_chat_denied(message, sender)
    send_to_ui("Received", message)
  end

  def bye_message(name)
    access_resource{ |rq, friends, request_table|
      if friends.has_key? name
        if @friends[name]
          port, ip  = friends[name][:port], friends[name][:ip]
          @client.send("BYE #{@name} #{@ip} #{@port}", 0, ip, port)
        else
          send_to_ui("Error", "#{name} doesn't wanna talk to you")
        end
      else
        send_to_ui "Error", "#{name} is not in the list of your friend"
      end
    }
  end

  def handle_bye(message, sender)
    name, ip, port = message.split(/\s+/)[1..-1]
    access_resource{|rq, friends, request_table|
      if friends[name]
        send_to_ui "Received", message
        @client.send("BYE #{@name} #{@ip} #{@port}", 0, sender[2], sender[1])
        friends.delete name
      end
    }
  end

  def access_resource(&block)
    @resource_semaphore.synchronize{
      block.call(@rq, @friends, @request_table)
    }
  end

  def send_to_ui(type, message)
    puts message
    @client.send({type: "client", message: "#{Time.new.inspect} #{type} #{message}", sender: "#{@name}-#{@port}", ip: @ip}.to_json, 0 , @ui_ip, @ui_port)
  end

end
