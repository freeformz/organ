require 'scrolls'
require 'base64'
require 'securerandom'
require 'forwardable'

require 'net/ssh'


Thread.abort_on_exception = true

module Organ

  class ServerCell
    extend Forwardable

    attr_accessor :logger

    def_delegators :logger, :log

    def initialize(params={})
      @logger   = Scrolls
      @hostname = params[:hostname]
      @user     = params[:user]
      @key      = params[:key]
    end

    def run
      log(fn: :run) do
        Net::SSH.start(@hostname, @user, :keys_only => true, :key_data => @key) do |ssh|
          loop do
            log(fn: :run, inside_ssh_loop: true)
            results = ssh.exec!("ls /")
            log(fn: :run, results: results)
            log(fn: :run, sleep: sleep(30))
          end
        end
      end
    end
  end

  class Tissue
    extend Forwardable

    attr_accessor :logger

    def_delegators :logger, :log

    def initialize(conn, cell_class)
      @logger = Scrolls
      @conn = conn
      @uuid = "tissue_#{SecureRandom::uuid.gsub(/-/,"_")}"
      @cell_class = cell_class
      @cells = {}
    end

    def run
      @conn.set_application_name @uuid
      @conn.listen_for @uuid
      work
    end

    def work
      loop do
        @conn.wait_for_notify do |event, pid, payload|
          case event
          # Message to the Tissue to control cells
          when @uuid
            payload = restore_payload(payload) || {}
            log(fn: :work, received_control_call: true, payload: payload)
            case payload[:command]
            when :start_cell
              cell_id = payload[:id]
              if cell = @cells[cell_id] && cell.alive?
                error_response :cell_already_alive, cell_id
              else
                params = payload[:params].clone
                log(fn: :work, starting_cell: cell_id) do
                  @cells[cell_id] = Thread.new do
                    cell = @cell_class.new(params)
                    cell.run
                  end
                end
              end
            when :stop_cell
              cell_id = payload[:id]
              if cell = @cells.delete(cell_id)
                cell.kill
              end
            end
          end
        end
      end
    end

    def restore_payload(payload)
      begin
        log(fn: :restore_payload) do
          Marshal.restore(Base64.decode64(payload))
        end
      rescue TypeError => e
        nil
      end
    end

    def error_response(msg, payload)
      @conn.notify msg, payload
    end
  end
end
