module Orchestra
  class ThreadPool
    def self.build count
      instance = new
      instance.count = count
      instance
    end

    def self.default
      build 1
    end

    attr :queue, :timeout

    def initialize args = {}
      @timeout, _ = Util.extract_key_args args, :timeout_ms => 1000
      @threads = Set.new
      @dead_pool = Set.new
      @pool_lock = Mutex.new
      @queue = Queue.new
      @jobs = {}
    end

    def enqueue &work
      job = Job.new work
      job.add_observer self
      while_locked do queue << job end
      job
    end

    def perform &work
      job = enqueue &work
      job.wait
    end

    def count
      threads.size
    end

    def count= new_count
      while_locked do
        loop do
          case @threads.size <=> new_count
          when 0 then return
          when -1 then add_thread!
          when 1 then remove_thread!
          end
        end
      end
    end

    def add_thread
      while_locked do add_thread! end
    end

    def remove_thread
      while_locked do remove_thread! end
    end

    def shutdown
      self.count = 0
    end

    def status
      while_locked do @threads.map &:status end
    end

    def threads
      while_locked do @threads end
    end

    def update event, *;
      reap_dead_pool if event == :failed
    end

    def with_timeout &block
      Timeout.timeout Rational(timeout, 1000), &block
    end

    private

    def add_thread!
      wait_for_thread_count_to_change do
        thr = Thread.new &method(:thread_loop)
        @threads << thr
      end
      true
    end

    def reap_dead_pool
      @dead_pool.each &:join
      @dead_pool.clear
    end

    def remove_thread!
      wait_for_thread_count_to_change do queue << :terminate end
      sleep Rational(1, 10000) # FIXME
      true
    end

    class Job
      include Observable

      attr :block, :error

      def initialize block
        @block = block
        @output_queue = Queue.new
      end

      def done?
        not @output_queue.empty?
      end

      def perform
        @output_queue.push block.call
      end

      def set_error error
        @error = error
        @output_queue.push Failed
      end

      def wait
        result = @output_queue.pop
        changed
        if result == Failed
          notify_observers :failed, error
          raise error
        else
          notify_observers :finished, result
        end
        result
      end

      Failed = Module.new
    end

    def thread_loop
      Thread.current.abort_on_exception = false
      until (job = queue.pop) == :terminate
        job.perform
      end
    rescue => error
      add_thread!
      job.set_error error
    ensure
      @threads.delete Thread.current
      @dead_pool << Thread.current
    end

    def wait_for_thread_count_to_change
      old_count = queue.num_waiting
      yield
    ensure
      Thread.pass while queue.num_waiting == old_count
    end

    def while_locked &block
      @pool_lock.synchronize do with_timeout &block end
    end
  end
end
