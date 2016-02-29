require "../foreman.cr"
require "./process.cr"
require "./procfile.cr"
require "./timeout.cr"

module Foreman
  class Engine
    # The signals that the engine cares about.
    HANDLED_SIGNALS = [:TERM, :INT, :HUP]
    COLORS = %i(green
     yellow
     blue
     magenta
     cyan
     light_gray
     dark_gray
     light_red
     light_green
     light_yellow
     light_blue
     light_magenta
     light_cyan
    )
    ERROR_COLOR = :red
    SYSTEM_COLOR = :white

    property :writer

    # Create an *Engine* for running processes
    #
    # @param [Hash] options
    #
    # @option options [Fixnum] :port      (5000)     The base port to assign to processes
    # @option options [String] :root      (Dir.pwd)  The root directory from which to run processes
    def initialize
      # _, @output = IO.pipe(write_blocking: true)
      # @output.colorize
      @output = STDOUT
      @channel = Channel(Int32).new
      @processes = [] of Foreman::Process
      @running = {} of Int32 => Foreman::Process
      @terminating = false
    end

    # Register processes by reading a Procfile
    #
    # @param [String] filename  A Procfile from which to read processes to register
    def load_procfile(filename : String)
      root = File.dirname(filename)
      Foreman::Procfile.new(filename).entries do |name, command|
        register name, command
      end
    end

    # Register a process to be run by this *Engine*
    #
    # @param [String] name     A name for this process
    # @param [String] command  The command to run
    private def register(name : String, command : String)
      @processes << Foreman::Process.new(name, command)
    end


    # Start the processes registered to this *Engine*
    #
    def start
      # write "starting", :blue
      # register_signal_handlers
      # startup
      spawn_processes
      watch_for_ended_processes
      # sleep 0.1
      # watch_for_termination { terminate_gracefully }
      # shutdown
    end

    private def write(string : String, color = SYSTEM_COLOR : Symbol)
      # @writer << string.colorize(color)
      @output << "#{string}\n".colorize(color)
    end

    private def spawn_processes
      @processes.each_with_index do |process, index|
        name = process.name
        color = COLORS[index]
        begin
          process.run do |output, error|
            spawn do
              spawn do
                while process_output = output.gets
                  write build_output(name, process_output), color
                end
              end
              spawn do
                while process_error = error.gets
                  write build_output(name, process_error), ERROR_COLOR
                end
              end

              status = process.wait
              @channel.send process.pid
            end
          end

          @running[process.pid] = process
          write build_output(name, "started with pid #{process.pid}"), color
        rescue #Errno::ENOENT
          write build_output(name, "unknown command: #{process.command}"), ERROR_COLOR
        end
      end
    end

    private def build_output(name, output)
      longest_name = @processes.map { |p| p.name.size }.max

      filler_spaces = ""
      (longest_name - name.size).times do
        filler_spaces += " "
      end

      "#{Time.now.to_s("%H:%M:%S")} #{name} #{filler_spaces}| #{output.to_s}"
    end

    private def watch_for_ended_processes
      if ended_pid = @channel.receive
        ended_process = @running[ended_pid]

        if id = @running.delete ended_pid
          terminate_gracefully
        end

        write build_output(ended_process.name, "exited!")
      end
    end

    private def kill_children(signal = Signal::TERM)
      @running.each do |pid|
        spawn do
          ::Process.kill signal, pid
          @running.delete pid
          puts pid
          @channel.send pid
        end
      end
    end

    private def terminate_gracefully
      return if @terminating
      # restore_default_signal_handlers
      @terminating = true

      write "sending SIGTERM to all processes"
      kill_children Signal::TERM

      timeout = 3
      Timeout.timeout(timeout) do
        while @running.size > 0
          puts @running.size
          sleep 0.1
        end
      end
    rescue Timeout::Error
      write "sending SIGKILL to all processes"
      kill_children Signal::KILL
    end








    # Get the process formation
    #
    # @returns [Fixnum]  The formation count for the specified process
    #
    # def formation
    #   @formation ||= parse_formation(options[:formation])
    # end

    # private def parse_formation(formation)
    #   pairs = formation.to_s.gsub(/\s/, "").split(",")

    #   pairs.inject(Hash.new(0)) do |ax, pair|
    #     process, amount = pair.split("=")
    #     if process == "all"
    #       ax.default = amount.to_i
    #     else
    #       ax[process] = amount.to_i
    #     end
    #     ax
    #   end
    # end

    # Set up deferred signal handlers
    #
    # def register_signal_handlers
      # HANDLED_SIGNALS.each do |sig|
        # if ::Signal.list.include? sig.to_s
        #   trap(sig) { Thread.main[:signal_queue] << sig; notice_signal }
        # end
    #   end
    # end

    # Unregister deferred signal handlers
    #
    # def restore_default_signal_handlers
    #   HANDLED_SIGNALS.each do |sig|
    #     trap(sig, :DEFAULT) if ::Signal.list.include? sig.to_s
    #   end
    # end

    # Wake the main thread up via the selfpipe when there's a signal
    #
    # def notice_signal
    #   @selfpipe[:writer].write_nonblock('.')
    # rescue Errno::EAGAIN
    #   # Ignore writes that would block
    # rescue Errno::EINT
    #   # Retry if another signal arrived while writing
    #   retry
    # end

    # Invoke the real handler for signal *sig*. This shouldn't be called directly
    # by signal handlers, as it might invoke code which isn't re-entrant.
    #
    # @param [Symbol] sig  the name of the signal to be handled
    #
    # def handle_signal(sig)
    #   case sig
    #   when :TERM
    #     handle_term_signal
    #   when :INT
    #     handle_interrupt
    #   when :HUP
    #     handle_hangup
    #   else
    #     system "unhandled signal #{sig}"
    #   end
    # end

    # Handle a TERM signal
    #
    # def handle_term_signal
    #   puts "SIGTERM received"
    #   terminate_gracefully
    # end

    # Handle an INT signal
    #
    # def handle_interrupt
    #   puts "SIGINT received"
    #   terminate_gracefully
    # end

    # Handle a HUP signal
    #
    # def handle_hangup
    #   puts "SIGHUP received"
    #   terminate_gracefully
    # end

    # Clear the processes registered to this *Engine*
    #
    # def clear
    #   @names = Hash.new
    #   @processes = [Foreman::Process]
    # end


    # Load a .env file into the *env* for this *Engine*
    #
    # @param [String] filename  A .env file to load into the environment
    #
    # def load_env(filename)
    #   Foreman::Env.new(filename).entries do |name, value|
    #     @env[name] = value
    #   end
    # end

    # Send a signal to all processes started by this *Engine*
    #
    # @param [String] signal  The signal to send to each process
    #
    # def kill_children(signal = "SIGTERM")
    #   begin
    #     Process.kill signal, *@running.keys unless @running.empty?
    #   rescue Errno::ESRCH | Errno::EPERM
    #   end
    # end

    # Send a signal to the whole process group.
    #
    # @param [String] signal  The signal to send
    #
    # def killall(signal = "SIGTERM")
    #   begin
    #     Process.kill "-#{signal}", Process.pid
    #   rescue Errno::ESRCH | Errno::EPERM
    #   end
    # end

    # List the available process names
    #
    # @returns [Array]  A list of process names
    #
    # def process_names
    #   @processes.map { |p| @names[p] }
    # end

    # Get the *Process* for a specifid name
    #
    # @param [String] name  The process name
    #
    # @returns [Foreman::Process]  The *Process* for the specified name
    #
    # def process(name)
    #   @names.invert[name]
    # end

    # Yield each *Process* in order
    #
    # def each_process
    #   process_names.each do |name|
    #     yield name, process(name)
    #   end
    # end

    # Get the root directory for this *Engine*
    #
    # @returns [String]  The root directory
    #
    # def root
    #   File.expand_path(options[:root] || Dir.pwd)
    # end

    # Get the port for a given process and offset
    #
    # @param [Foreman::Process] process   A *Process* associated with this engine
    # @param [Fixnum]           instance  The instance of the process
    #
    # @returns [Fixnum] port  The port to use for this instance of this process
    #
    # def port_for(process, instance, base = nil)
    #   if base
    #     base + (@processes.index(process.process) * 100) + (instance - 1)
    #   else
    #     base_port + (@processes.index(process) * 100) + (instance - 1)
    #   end
    # end

    # Get the base port for this foreman instance
    #
    # @returns [Fixnum] port  The base port
    #
    # def base_port
      # (options[:port] || env["PORT"] || ENV["PORT"] || 5000).to_i
    #   5000
    # end


    # # Helpers ##########################################################


    # private def name_for(pid)
    #   process, index = @running[pid]
    #   name_for_index(process, index)
    # end

    # private def name_for_index(process : Foreman::Process, index : Int)
    #   [@names[process], index.to_s].compact.join(".")
    # end

    # private def output_with_mutex(name, message)
    #   @mutex.synchronize do
    #     output name, message
    #   end
    # end

    # private def system(message)
    #   output_with_mutex "system", message
    # end

    # private def termination_message_for(status)
    #   if status.exited?
    #     "exited with code #{status.exitstatus}"
    #   elsif status.signaled?
    #     "terminated by SIG#{Signal.list.invert[status.termsig]}"
    #   else
    #     "died a mysterious death"
    #   end
    # end

    # private def flush_reader(reader)
    #   until reader.eof?
    #     data = reader.gets
    #     output_with_mutex name_for(@readers.key(reader)), data
    #   end
    # end

    # # Engine ###########################################################

    # private def read_self_pipe
    #   @selfpipe[:reader].read_nonblock(11)
    # rescue Errno::EAGAIN | Errno::EINTR | Errno::EBADF
    #   # ignore
    # end

    # private def handle_signals
    #   while sig = Thread.main[:signal_queue].shift
    #     self.handle_signal(sig)
    #   end
    # end

    # private def handle_io(readers)
    #   readers.each do |reader|
    #     next if reader == @selfpipe[:reader]

    #     if reader.eof?
    #       @readers.delete_if { |key, value| value == reader }
    #     else
    #       data = reader.gets
    #       output_with_mutex name_for(@readers.invert[reader]), data
    #     end
    #   end
    # end

    # private def watch_for_output
    #   Thread.new do
    #     begin
    #       loop do
    #         io = IO.select([@selfpipe[:reader]] + @readers.values, nil, nil, 30)
    #         read_self_pipe
    #         handle_signals
    #         handle_io(io ? io.first : Array.new)
    #       end
    #     rescue ex : Exception
    #       puts ex.message
    #       puts ex.backtrace
    #     end
    #   end
    # end

    # private def watch_for_termination
    #   pid, status = Process.wait2
    #   output_with_mutex name_for(pid), termination_message_for(status)
    #   @running.delete(pid)
    #   yield if block_given?
    #   pid
    # rescue Errno::ECHILD
    # end

    # private def terminate_gracefully
    #   return if @terminating
    #   restore_default_signal_handlers
    #   @terminating = true

    #   system "sending SIGTERM to all processes"
    #   kill_children "SIGTERM"

    #   timeout = 60
    #   Timeout.timeout(timeout) do
    #     while @running.length > 0
    #       watch_for_termination
    #     end
    #   end
    # rescue Timeout::Error
    #   system "sending SIGKILL to all processes"
    #   kill_children "SIGKILL"
    # end
  end
end
