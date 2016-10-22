load('Semaphore.rb')
require 'socket'
require 'thread'
require 'json'


class ChatServer
  MAX_SIZE = 5
  @@host = 'localhost'
  def initialize(host, port)
    @ip = host
    @port = port
    @server = UDPSocket.new
    @server.bind(host, port)
    @semaphore = Mutex.new
    @storage = {}
    if not File.exist?("server_#{port}.txt")
      File.new("server_#{port}.txt", "w+")
      @storage = {}
    else
      File.open("server_#{port}.txt", 'r'){ |f|
        @storage = JSON.parse(f.gets || "{}")
      }
    end
    loop do
      msg, sender = @server.recvfrom(140)
      puts sender[1], sender[2]
      handle_message(msg, sender)
    end
  end
  def handle_message(message, sender)
    partitions = message.split(/\s+/)
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
    else

    end
    handler.run

  end


  def handle_register(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    request = access_storage(lambda{ |storage|
      if storage[name]
        @server.send("REGISTERED #{rq}", 0, sender[2], sender[1])
      elsif storage.length < MAX_SIZE
        storage[name] = {ip: sender[2]}
        @server.send("REGISTERED #{rq}", 0, sender[2], sender[1])
      else
        @next_server ||= ChatServer.new(port + 1)
        @server.send("REGISTER-DENIED #{rq} #{@next_server.ip} #{@next_server.port}", 0, sender[2], sender[1])
      end
    })
  end

  def handle_publish(sender_message, sender)
    rq, name, port, status, *list_of_names = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda{ |storage|
      if storage[name] && (status.upcase == 'ON' || status.upcase == 'OFF')
        storage[name][:publish] = {
          status: status,
          port: port,
          names: list_of_names
        }
        @server.send((["PUBLISHED"] + sender_message.split(/\s+/)[1..-1]).join(' '), 0, sender[2], sender[1])
      else
        puts sender_message
        @server.send("UNPUBLISHED #{rq}", 0, sender[2], sender[1])
      end
    })
  end

  def handle_information_req(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda { |storage|
      if storage[name]
        publish = storage[name][:publish]
        port, status, list_of_names = publish[:port], publish[:status], publish[:names]
        @server.send("INFORMResp #{rq} #{name} #{port} #{status} #{list_of_names}", 0, sender[2], sender[1])
      else
        return nil
      end
    })
  end

  def handle_find_req(sender_message, sender)
    rq, name = sender_message.split(/\s+/)[1..-1]
    access_storage(lambda {|storage|
      if storage[name]
        found_client = storage[name]
        if found_client[:publish][:status].upcase == 'ON'
          @server.send("FINDResp #{rq} #{name} #{found_client[:publish][:port]} #{found_client[:ip]}", 0, sender[2], sender[1])
        else
          @server.send("FINDDenied #{rq} #{other_name}", 0, sender[2], sender[1])
        end
      else
        @server.send("REFER #{rq} #{@next_server.ip_address} #{@next_server.port}", 0, sender[2], sender[1])
      end
    })
  end

  def access_storage(func)
    @semaphore.synchronize{
      func.call(@storage)
      File.open("server_#{port}.txt", "w+") do |f|
        f.write("@storage.to_json")
      end
    }
  end
end

ChatServer.new('localhost', 9999)
