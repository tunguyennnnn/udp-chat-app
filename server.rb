require 'string-encrypt'
require 'socket'
require 'thread'
require 'json'


class ChatServer
  MAX_SIZE = 5
  @@host = 'localhost'

  attr_accessor :adjacent_servers
  def initialize(host, port)
    @ip = host
    @port = port
    @server = UDPSocket.new
    @adjacent_servers = AdjacentServers.new
    @semaphore = Mutex.new
    @register_semaphore = Mutex.new
    @registered_queue = {}
    @storage = {}
    if not File.exist?("server_#{port}.txt")
      File.new("server_#{port}.txt", "w+")
      @storage = {}
    else
      File.open("server_#{port}.txt", 'r'){ |f|
        @storage = JSON.parse(f.gets || "{}")
      }
    end
  end

  def start_server
    @server.bind(@ip, @port)
    send_to_ui("Server start", "")
    loop do
      msg, sender = @server.recvfrom(140)
      puts sender[1], sender[2]
      handle_message(msg, sender) #put thread here
    end
  end

  def add_ui_address(ui_server, ui_port)
    @ui_ip = ui_server
    @ui_port = ui_port
  end

  def handle_message(message, sender)
    partitions = message.split(/\s+/)
    send_to_ui("Server Received", message)
    puts message
    case partitions[0]
    when "REGISTER"
      handler = Thread.new{handle_register(message, sender)}
    when "PUBLISH"
      handler = Thread.new{handle_publish(message, sender)}
    when "INFORMReq"
      handler = Thread.new{handle_information_req(message, sender)}
    when "FINDReq"
      handler = Thread.new{handle_find_req(message, sender)}
    when "SERVERReq"
      handler = Thread.new{handle_server_req_message(message, sender)}
    when 'SERVERAns'
      handler = Thread.new(handle_server_ans_message(message, sender))
    else
      # should do anything
    end
    if handler
      handler.run
    end

  end

  def handle_server_ans_message(message, sender)
    type, name, bool = message.split(/\s+/)[1..-1]
    if bool == 'true'
      access_registered_queue(lambda {|registered_queue|
        registered_queue[name].call(nil)
        registered_queue.delete(name)
      })
    end
  end

  def handle_server_req_message(message, sender)
    type = message.split(/\s+/)[1]
    case type
    when "is_registered?"
      is_registered?(message)
    else
    end
  end

  def is_registered?(message)
    name, ip, port = message.split(/\s+/)[2..-1]
    access_storage(lambda {|storage|
      if ip  == @ip && port == @port.to_s
        access_registered_queue(lambda {|registered_queue|
          if registered_queue[name]
            registered_queue[name].call(true, storage)
          end
        })
      else
        access_registered_queue(lambda {|registered_queue|
          if registered_queue[name]
          else
            if storage[name] || registered_queue[name]
              registered_queue.delete(name)
              @server.send("SERVERAns REGISTERED #{name} true", 0, ip, port)
            else
              @server.send(message, 0, @adjacent_servers.next_server_ip, @adjacent_servers.next_server_port)
            end
          end
        })
      end
    })
  end

  def handle_register(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda{ |storage|
      if storage[name] #if user has registered to this server --> considered it as a re-register
        @server.send("REGISTERED #{rq}", 0, sender[2], sender[1])

      elsif storage.length < MAX_SIZE
        # else if the server can take the user
        # first push the user register decision in to a queue
        # then find out if the user has registered in other server
        # after being answered by other servers, lambda with appropriate parameters will be sent to make decision
        check_message = "SERVERReq is_registered? #{name}"
        access_registered_queue(lambda {|registered_queue|
          registered_queue[name] = lambda { |can_register, storage, other_ip = nil, other_port = nil|
            if can_register
              storage[name] = {}
              storage[name]["ip"] = sender[2]
              @server.send("REGISTERED #{rq}", 0, sender[2], sender[1])
            else
              @server.send("REGISTER-DENIED #{rq} #{other_ip} #{other_port}", 0, sender[2], sender[1])
            end
          }
        })
        @server.send("SERVERReq is_registered? #{name} #{@ip} #{@port}", 0, @adjacent_servers.next_server_ip, @adjacent_servers.next_server_port)
      else #if @server is full of users, refer the user to another server
        @server.send("REGISTER-DENIED #{rq} #{@adjacent_servers.next_server_ip} #{@adjacent_servers.next_server_port}", 0, sender[2], sender[1])
      end
    })
  end

  def handle_publish(sender_message, sender)
    rq, name, port, status, *list_of_names = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda{ |storage|
      if storage[name] && (status.upcase == 'ON' || status.upcase == 'OFF')
        token = status + "-" + list_of_names.join(name)
        storage[name]["publish"] = {}
        storage[name]["publish"]["status"] = status
        storage[name]["publish"]["port"] = port
        storage[name]["publish"]["names"] = list_of_names
        storage[name]["publish"]["token"] = token
        @server.send("PUBLISHED #{sender_message.split(/\s+/)[1..-1].join(' ')} #{token}", 0, sender[2], sender[1])
      else
        @server.send("UNPUBLISHED #{rq}", 0, sender[2], sender[1])
      end
    })
  end

  def handle_information_req(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda {|storage|
      if storage[name]
        publish = storage[name]["publish"]
        port, status, list_of_names = publish["port"], publish["status"], publish["names"]
        @server.send("INFORMResp #{rq} #{name} #{port} #{status} #{list_of_names}", 0, sender[2], sender[1])
      else
        @server.send("INFORM-REQ-DENIED #{rq}", 0, sender[2], sender[1])
      end
    })
  end

  def handle_find_req(sender_message, sender)
    rq, friend_name, my_name = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda {|storage|
      puts "aaaaa"
      if storage[friend_name]
        puts "bbbbb"
        found_client = storage[friend_name]
        puts found_client
        if found_client["publish"]
          puts found_client["publish"]["names"]
          if !found_client["publish"]["names"].include? my_name.upcase
            @server.send("FINDDenied #{rq} #{friend_name}", 0, sender[2], sender[1])
          elsif found_client["publish"]["status"].upcase == 'ON'
            @server.send("FINDResp #{rq} #{friend_name} #{found_client["publish"]["port"]} #{found_client["ip"]} #{found_client["publish"]["token"]}", 0, sender[2], sender[1])
          else
            @server.send("FINDResp #{rq} #{friend_name} OFF", 0, sender[2], sender[1])
          end
        else
          @server.send("FINDDenied #{rq} #{friend_name}", 0, sender[2], sender[1])
        end
      else
        @server.send("REFER #{rq} #{friend_name} #{@adjacent_servers.next_server_ip} #{@adjacent_servers.next_server_port}", 0, sender[2], sender[1])
      end
    })
  end


  def access_storage(func)
    @semaphore.synchronize{
      func.call(@storage)
      File.open("server_#{@port}.txt", "w+") do |f|
        puts @storage
        f.write(@storage.to_json)
      end
    }
  end

  def access_registered_queue(func)
    @register_semaphore.synchronize{
      func.call(@registered_queue)
    }
  end

  def send_to_ui(type, message)
    @server.send({type: "server", message: "#{Time.new.inspect} #{type} #{message}", sender: "server-#{@port}", ip: @ip}.to_json, 0 , @ui_ip, @ui_port)
  end
end

class AdjacentServers
  attr_reader :next_server_ip
  attr_reader :next_server_port
  attr_reader :previous_server_port
  attr_reader :previous_server_ip
  def previous_server(ip, port)
    @previous_server_port = port
    @previous_server_ip = ip
  end

  def next_server(ip, port)
    @next_server_port = port
    @next_server_ip = ip
  end

  def next_server?
    return @next_server_ip && @next_server_port
  end

  def previous_server?
    return @previous_server_ip && @previous_server_port
  end
end
