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

  EXEC_TABLE = ["register", "find_user", "inform_request", "chat_message", "bye_message"]

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
        text, sender = @client.recvfrom(140)
        handle_message(text, sender)
      }
    end
  end

  # handle message sent from other sockets:
  def handle_message(message, sender)
    partition = message.split(/\s+/) #parsing the message
    message_type = partition[0]
    if message_type.upcase == "EXEC" #exec is used to execute commands from the ui
      func_name, *params = partition[1..-1]
      if EXEC_TABLE.include? func_name
        send(func_name, *params)
      end
    else
      func_name = partition[0].downcase.sub('-', '_')
      Thread.new {
        send("handle_#{func_name}",message, sender)
      }.join

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
    end
    TIMES_REPEATED.times do
      sleep(2)
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
    rq = message.split(/\s+/)[1]
    ip ,port = sender[2], sender[1]
    access_resource{|rq, friends, request_table|
      #if rq corresponds to what stored into requestable -> registered and clean the register table
      if (request_table["REGISTER"] && request_table["REGISTER"][rq.to_s])
        @server_port = ip
        @server_port = port
        request_table["REGISTER"].delete rq.to_s
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_register_denied(message)
    rq, next_server_ip, next_port = message.split(/\s+/)[1..-1]
    correct_rq = nil
    access_resource{|rq, friends, request_table|
      if (request_table["REGISTER"] && request_table["REGISTER"][rq.to_s])
        request_table["REGISTER"].delete rq.to_s
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
      rq_number = rq.to_s
      message = "PUBLISH #{rq} #{@name} #{@port} #{status} #{list_of_names.join(' ')}"
      request_table["PUBLISH"] = request_table["PUBLISH"] || {}
      request_table["PUBLISH"][rq_number] = lambda{
        @client.send(message, 0, @server_ip, @server_port)
      }
      @client.send(message, 0, @server_ip, @server_port)
    }

    TIMES_REPEATED.times do
      sleep(0.5)
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
    rq = message.split(/\s+/)
    access_resource{|rq, friends, request_table|
      if request_table["PUBLISH"] && request_table["PUBLISH"][rq.to_s]
        request_table["PUBLISH"].delete rq.to_s
        send_to_ui("Received", message)
        @token = message.split(/\s+/).last()
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_unpublished(message, sender)
    rq = message.split(/\s+/)[1]
    access_resource {|rq, friends, request_table|
      if request_table["PUBLISH"] && request_table["PUBLISH"][rq.to_s]
        request_table["REGISTER"].delete rq.to_s
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
    }

    TIMES_REPEATED.times do
      sleep(0.5)
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
    rq = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["INFORM"] && request_table["INFORM"][rq.to_s]
        request_table["INFORM"].delete rq.to_s
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_informdenied
    rq = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["INFORM"] && request_table["INFORM"][rq.to_s]
        request_table["INFORM"].delete rq.to_s
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
    rq, name, port, ip, token  = message.split(/\s+/)[1..-1]
    access_resource do |rq, friends, request_table|
      if request_table["FIND"] && request_table["FIND"][rq.to_s]
        request_table["FIND"].delete  rq
        friends[name] = {port: port, ip: ip, token: token}
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    end
  end

  def handle_finddenied(message, sender)
    rq = message.split(/\s+/)[1]
    access_resource{|rq, friends, request_table|
      if request_table["FIND"] && request_table["FIND"][rq.to_s]
        request_table["FIND"].delete rq.to_s
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  def handle_refer(message, sender)
    rq, ip, port = message.split(/\s+/)[1..-1]
    access_resource{|rq, friends, request_table|
      if request_table["FIND"] && request_table["FIND"][rq.to_s]
        request_table["FIND"].delete rq.to_s
        send_to_ui("Received", message)
      else
        send_to_ui("Error", "Received authorized message: #{message}")
      end
    }
  end

  ##################### CHAT #########################
  def chat_message(name, text)
    access_resource{ |rq, friends, request_table|
      if friends.has_key? name
        if friends[name]
          port, ip, token = friends[name][:port], friends[name][:ip], friends[name][:token]
          if token
            message = "CHAT #{token} #{@name} #{@ip} #{@port} "
          else
            message = "CHAT #{@name} #{@ip} #{@port} "
          end
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
    }
  end

  def handle_chat(message, sender)
    token, name, ip, port, text =  message.split(/\s+/)[1..-1]
    if token != @token
      @client.send("Error: You cannot talk to me", 0, sender[2], sender[1])
    else
      access_resource{|rq, friends, request_table|
        friends[name] = {port: port, ip: ip}
        send_to_ui("Received", message)
      }
    end
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
