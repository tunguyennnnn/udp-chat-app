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

  HANDLE__MESSAGE_LIST = ["REGISTER", "PUBLISH", "INFORMReq", "FINDReq", "SERVERReq", "SERVERAns"]
  def handle_message(message, sender)
    partitions = message.split(/\s+/)
    send_to_ui("Server Received", message)
    puts message
    if HANDLE__MESSAGE_LIST.include? partitions[0]
        funcname = "handle_#{partitions[0].downcase}"
        Thread.new{
          send(funcname, message, sender)
        }.run
    end
  end

  def handle_serverans(message, sender)
    type, name, bool = message.split(/\s+/)[1..-1]
    if bool.to_s == 'true'
      access_registered_queue{|registered_queue|
        puts "xxxxxx"
        registered_queue[name].call(nil, registered_queue, sender[2], sender[1])
        registered_queue.delete(name)
      }
    end
  end

  def handle_serverreq(message, sender)
    type = message.split(/\s+/)[1]
    case type
    when "is_registered?"
      is_registered?(message)
    else
    end
  end

  def is_registered?(message)
    name, ip, port = message.split(/\s+/)[2..-1]
    access_storage{|storage|
      if ip  == @ip && port == @port.to_s
        access_registered_queue{|registered_queue|
          if registered_queue[name]
            registered_queue[name].call(true, storage)
          end
        }
      else
        access_registered_queue{|registered_queue|
          if storage[name] || registered_queue[name]
            registered_queue.delete(name)
            @server.send("SERVERAns REGISTERED #{name} true", 0, ip, port)
          else
            @server.send(message, 0, @adjacent_servers.next_server_ip, @adjacent_servers.next_server_port)
          end
        }
      end
    }
  end

  def handle_register(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    access_storage{ |storage|
      if storage[name] #if user has registered to this server --> considered it as a re-register
        @server.send("REGISTERED #{rq}", 0, sender[2], sender[1])
      else
        # else if the server can take the user
        # first push the user register decision in to a queue
        # then find out if the user has registered in other server
        # after being answered by other servers, lambda with appropriate parameters will be sent to make decision
        check_message = "SERVERReq is_registered? #{name}"
        access_registered_queue{|registered_queue|
          registered_queue[name] = lambda { |can_register, storage, other_ip = nil, other_port = nil|
            if can_register && storage.length < MAX_SIZE
              storage[name] = {}
              storage[name]["ip"] = sender[2]
              @server.send("REGISTERED #{rq}", 0, sender[2], sender[1])
            else
              @server.send("REGISTER-DENIED #{rq} #{other_ip} #{other_port}", 0, sender[2], sender[1])
            end
          }
        }
        @server.send("SERVERReq is_registered? #{name} #{@ip} #{@port}", 0, @adjacent_servers.next_server_ip, @adjacent_servers.next_server_port)
      end
    }
  end

  def handle_publish(sender_message, sender)
    rq, name, port, status, *list_of_names = sender_message.split(/\s+/)[1..-1]
    access_storage{ |storage|
      if storage[name] && (status.upcase == 'ON' || status.upcase == 'OFF')
        token = status + "-" + list_of_names.join(name) + name
        storage[name]["publish"] = {}
        storage[name]["publish"]["status"] = status
        storage[name]["publish"]["port"] = port
        storage[name]["publish"]["names"] = list_of_names
        storage[name]["publish"]["token"] = token
        @server.send("PUBLISHED #{sender_message.split(/\s+/)[1..-1].join(' ')} #{token}", 0, sender[2], sender[1])
      else
        @server.send("UNPUBLISHED #{rq}", 0, sender[2], sender[1])
      end
    }
  end

  def handle_informreq(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    access_storage{|storage|
      if storage[name]
        publish = storage[name]["publish"]
        port, status, list_of_names, token = publish["port"], publish["status"], publish["names"], publish["token"]
        @server.send("INFORMResp #{rq} #{name} #{port} #{status} #{list_of_names} #{token}", 0, sender[2], sender[1])
      else
        @server.send("INFORM-REQ-DENIED #{rq}", 0, sender[2], sender[1])
      end
    }
  end

  def handle_findreq(sender_message, sender)
    rq, friend_name, my_name = sender_message.split(/\s+/)[1..-1]
    access_storage{|storage|
      if storage[friend_name]
        found_client = storage[friend_name]
        if found_client["publish"]
          if !found_client["publish"]["names"].include? my_name
            @server.send("FINDDenied #{rq} #{friend_name}", 0, sender[2], sender[1])
          elsif found_client["publish"]["status"].upcase == 'ON'
            @server.send("FINDResp #{rq} #{friend_name} #{found_client["publish"]["port"]} #{found_client["ip"]} #{my_name + friend_name}", 0, sender[2], sender[1])
          else
            @server.send("FINDResp #{rq} #{friend_name} OFF", 0, sender[2], sender[1])
          end
        else
          @server.send("FINDDenied #{rq} #{friend_name}", 0, sender[2], sender[1])
        end
      else
        @server.send("REFER #{rq} #{friend_name} #{@adjacent_servers.next_server_ip} #{@adjacent_servers.next_server_port}", 0, sender[2], sender[1])
      end
    }
  end

  def access_storage(&block)
    @semaphore.synchronize{
      block.call(@storage)
      File.open("server_#{@port}.txt", "w+") do |f|
        puts @storage
        f.write(@storage.to_json)
      end
    }
  end

  def access_registered_queue(&block)
    @register_semaphore.synchronize{
      block.call(@registered_queue)
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
