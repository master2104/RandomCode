module RbWinDBG

	#
	# Snapshot Target Process threads and Memory Blocks
	# 	Uses PyDBG algorithm (as described by Pedram Amini in his Fuzzing book)
	#
	$rbWinDbgSnapshotDebug = false
	
	class Win32ProcessSnapshot
		
		attr_reader :snapshot_info
		
		def initialize(dbg)
			@dbg = dbg
			@snapshot_info = {}
		end
		
		#
		# Takes a snapshot of the current state of the Target process
		#
		#	Thread Context
		#	Writable Memory Pages
		#
		def snapshot!
			suspend_threads!
			
			@snapshot_info = {}
			@snapshot_info[:start_time] = Time.now
			@snapshot_info[:thread_count] = 0
			@snapshot_info[:memory_block_count] = 0
			@snapshot_info[:memory_store_count] = 0
			
			snapshot_threads()
			snapshot_memory()
			
			@snapshot_info[:finish_time] = Time.now
			
			resume_threads!
		end
		
		#
		# Restore the current state of the Target process to last stored
		# snapshot
		#
		def restore!
			suspend_threads!
			
			restore_memory()
			restore_threads()
			
			resume_threads!
		end
		
		private
		
		def snapshot_threads()
			@thread_snapshot = {}
			
			@dbg.threads.each do |tid|
				puts "Saving Context for TID: #{tid}" if $rbWinDbgSnapshotDebug
				
				@thread_snapshot[tid] = @dbg.get_thread_context(tid)
			end
			
			@snapshot_info[:thread_count] = @dbg.threads.size
		end
		
		def restore_threads()
			# We restore active threads only.
			@dbg.threads.each do |tid|
				puts "Restoring Context for TID: #{tid}" unless @thread_snapshot[tid].nil? or (!$rbWinDbgSnapshotDebug)
				
				@dbg.set_thread_context(tid, @thread_snapshot[tid]) unless @thread_snapshot[tid].nil?
			end
		end
		
		def snapshot_memory()
			@memory_snapshot = []
			
			protection_filters = [
				::Metasm::WinAPI::PAGE_READONLY, 
				::Metasm::WinAPI::PAGE_EXECUTE_READ, 
				::Metasm::WinAPI::PAGE_GUARD,
				::Metasm::WinAPI::PAGE_NOACCESS
			]
			addrsz = @dbg.process.addrsz
			cursor = 0
			
			while cursor < 0xFFFFFFFF
				mbi = ::Metasm::WinAPI.alloc_c_struct("MEMORY_BASIC_INFORMATION#{addrsz}")
				ret = ::Metasm::WinAPI.virtualqueryex(@dbg.process.handle, cursor, mbi, mbi.sizeof)
				
				break if ret == 0
				cursor += mbi.regionsize
				
				next unless (mbi.state & ::Metasm::WinAPI::MEM_COMMIT) > 0
				next if protection_filters.collect {|e| e if ((mbi.protect & e) > 0)}.compact.size() > 0
				
				puts "Saving Memory Block - BaseAddr: 0x%08x Size: 0x%08x" % 
					[mbi.baseaddress, mbi.regionsize] if $rbWinDbgSnapshotDebug
				
				mem_data = @dbg.read_memory(mbi.baseaddress, mbi.regionsize)
				raise "Data Inconsistency in Snapshot" if mem_data.size != mbi.regionsize
				
				@memory_snapshot << [mbi, mem_data]
				
				@snapshot_info[:memory_block_count] += 1
				@snapshot_info[:memory_store_count] += mbi.regionsize
			end
		end
		
		def restore_memory()
			@memory_snapshot.each do |ms|
				mbi = ms[0]
				mem_data = ms[1]
				
				puts "Restoring Memory Block - BaseAddr: 0x%08x Size: 0x%08x" % 
					[mbi.baseaddress, mbi.regionsize] if $rbWinDbgSnapshotDebug
				
				@dbg.write_memory(mbi.baseaddress, mem_data)
			end
		end
		
		def suspend_threads!
			@dbg.threads.each do |tid|
				@dbg.get_thread(tid).suspend()
			end
		end
		
		def resume_threads!
			@dbg.threads.each do |tid|
				@dbg.get_thread(tid).resume()
			end
		end
	end

end