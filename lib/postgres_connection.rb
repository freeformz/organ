require 'pg'
require 'scrolls'
require 'forwardable'
require 'uri'

class PostgresConnectionByURL
  extend Forwardable

  attr_accessor :logger

  def_delegators :logger, :log

  def_delegators :conn, :exec, :wait_for_notify, :finish

  def initialize(url)
    @logger = Scrolls
    @uri = URI.parse(url)
  end

  def unlisten(event)
    log(class: self.class, fn: :unlisten, event: event) do
      conn.exec("UNLISTEN #{event}")
    end
  end

  def listen_for(event)
    log(class: self.class, fn: :listen_for, event: event) do
      conn.exec("LISTEN #{event}")
    end
  end

  def notify(event, payload=nil)
    log(class: self.class, fn: :notify, event: event, payload: payload) do
      msg = "NOTIFY #{event}" 
      msg += ", '#{PGconn.escape_string(payload.to_s)}'" if payload
      conn.exec(msg)
    end
  end

  def set_application_name(app_name)
    log(class: self.class, fn: :set_connection_app_name, to: app_name) do
      conn.exec("set application_name = #{app_name}")
    end
  end

  private

  def conn
    @conn ||= log(class: self.class, fn: :conn, new: true) do
                opts = { host: @uri.host,
                       dbname: @uri.path[1..-1],
                     password: @uri.password,
                      sslmode: 'require',
                         port: @uri.port,
              connect_timeout: 20 }
                opts[:user] = @uri.user if @uri.user
                ::PGconn.new(opts)
              end
  end

end
