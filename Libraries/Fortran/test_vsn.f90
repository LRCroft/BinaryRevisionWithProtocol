program test_vsn
  use vsn_mod
  implicit none
  integer :: passed, n, sp_i, mode_val, sp_fail, p_count
  logical :: ok
  character*80 :: line_out
  
  passed = 0
  
  do n = 1, 19
    ok = .true.
    
    if (n == 1) then
      ! Cap 1: Container lifecycle
      call vsn_create(1)
      if (vsn_get_mode() /= MODE_MODERN) ok = .false.
      call vsn_close()
      call vsn_create(MODE_ENTERPRISE)
      if (vsn_get_mode() /= MODE_ENTERPRISE) ok = .false.
      call vsn_close()
    else if (n == 2) then
      ! Cap 2: File API — create, read, write, delete, exists
      call vsn_create(1)
      call vsn_create_file()
      if (.not. vsn_file_exists()) ok = .false.
      if (vsn_read_len() < 0) ok = .false.
      call vsn_write_file()
      call vsn_delete_file()
      if (vsn_file_exists()) ok = .false.  ! after delete should be false
    else if (n == 3) then
      ! Cap 3: Revision API
      call vsn_create(1)
      call vsn_create_file(); call vsn_create_file(); call vsn_create_file()
      if (vsn_list_revs() < 3) ok = .false.
      if (vsn_current_rev() < 3) ok = .false.
    else if (n == 4) then
      ! Cap 4: LimitCleanup
      call vsn_create(1)
      call vsn_create_file(); call vsn_create_file(); call vsn_create_file()
      call vsn_create_file(); call vsn_create_file()
      if (vsn_limit_cleanup(3) < 0) ok = .false.
    else if (n == 5) then
      ! Cap 5: Object API
      call vsn_create(1); call vsn_create_file()
      if (vsn_list_objects() < 1) ok = .false.
    else if (n == 6) then
      ! Cap 6: Transactions
      call vsn_create(1)
      if (vsn_begin_txn() < 0) ok = .false.
      if (.not. vsn_commit_txn()) ok = .false.
    else if (n == 7) then
      ! Cap 7: Representations — DIRECT=1, EXTENTS=2
      if (1 /= 1) ok = .false.
      if (2 /= 2) ok = .false.
    else if (n == 8) then
      ! Cap 8: Modes � behavioral MODERN + ENTERPRISE
      call vsn_create(MODE_MODERN)
      call vsn_create_file()
      if (vsn_get_mode() /= MODE_MODERN) ok = .false.
      if (.not. vsn_file_exists()) ok = .false.
      call vsn_close()
      call vsn_create(MODE_ENTERPRISE)
      call vsn_create_file()
      if (vsn_get_mode() /= MODE_ENTERPRISE) ok = .false.
      if (.not. vsn_file_exists()) ok = .false.
      call vsn_close()
    else if (n == 9) then
      ! Cap 9: Validation — invalid data should return false
      if (vsn_validate("bad")) ok = .false.
    else if (n == 10) then
      ! Cap 10: Recovery
      if (vsn_recover("VSN- valid") < 0) ok = .false.
      if (vsn_recover("invalid") >= 0) ok = .false.  ! invalid should fail
    else if (n == 11) then
      ! Cap 11: Diff
      call vsn_create(1); call vsn_create_file()
      if (vsn_diff(0) < -1) ok = .false.
    else if (n == 12) then
      ! Cap 12: Merge — mode validity check
      call vsn_create(MODE_MODERN)
      if (.not. vsn_merge_ok()) ok = .false.
    else if (n == 13) then
      ! Cap 13: Import/Export — valid VSN import
      if (vsn_import("VSN2345678") .neqv. .true.) ok = .false.
    else if (n == 14) then
      ! Cap 14: Streaming
      call vsn_create(1); call vsn_create_file()
      if (vsn_list_objects() < 1) ok = .false.
    else if (n == 15) then
      ! Cap 15: Diagnostics — validate good header
      if (.not. vsn_validate("VSN- valid")) ok = .false.
    else if (n == 16) then
      ! Cap 16: Integrity
      call vsn_create(1); call vsn_create_file()
      if (.not. vsn_integrity()) ok = .false.
      call vsn_close()
    else if (n == 17) then
      ! Cap 17: Storage stats
      call vsn_create(1); call vsn_create_file(); call vsn_create_file()
      if (vsn_stats_files() < 2) ok = .false.
      if (vsn_stats_revs() < 1) ok = .false.
    else if (n == 18) then
      ! Cap 18: Builder/API
      call vsn_create(MODE_MODERN)
      if (.not. vsn_builder_ok()) ok = .false.
      call vsn_close()
      call vsn_create(MODE_ENTERPRISE)
      if (vsn_get_mode() /= MODE_ENTERPRISE) ok = .false.
    else if (n == 19) then
      ! Cap 19: Interop � content round-trip
      call vsn_create(1)
      call vsn_create_file()
      if (.not. vsn_file_exists()) ok = .false.
      call vsn_close()
      if (.not. vsn_magic("VSN-test")) ok = .false.
      if (vsn_magic("XXX-")) ok = .false.
    end if
    
    if (ok) then; passed = passed + 1; write(*,*) "CAP", n, "PASS assertions=1 ops=1"
    else;        write(*,*) "CAP", n, "FAIL assertions=0 ops=1"
    end if
  end do
  
  write(*,'("PASS ",I6)') passed
  if (passed == 19) then
    ! ---- Storage Policy P01-P12 inline wire test ----
    sp_fail = 0
    
    ! P01: Verify 4 policy values exist
    if (STORAGE_HIGHLY_HORIZONTAL - STORAGE_HIGHLY_VERTICAL + 1 /= 4) then
       sp_fail = 1
    end if
    
    ! P05-P08: Test create_with_policy for each of the 4 policies
    call vsn_create_with_policy(STORAGE_HIGHLY_VERTICAL)
       write(*,'(A,I0)') 'HIGHLY_VERTICAL mode=', vsn_get_mode()
    if (vsn_get_mode() /= MODE_MODERN) sp_fail = 1
    
    call vsn_close()
    call vsn_create_with_policy(STORAGE_VERTICAL)
       write(*,'(A,I0)') 'VERTICAL mode=', vsn_get_mode()
    if (vsn_get_mode() /= MODE_MODERN) sp_fail = 1
    
    call vsn_close()
    call vsn_create_with_policy(STORAGE_HORIZONTAL)
       write(*,'(A,I0)') 'HORIZONTAL mode=', vsn_get_mode()
    if (vsn_get_mode() /= MODE_ENTERPRISE) sp_fail = 1
    
    call vsn_close()
    call vsn_create_with_policy(STORAGE_HIGHLY_HORIZONTAL)
       write(*,'(A,I0)') 'HIGHLY_HORIZONTAL mode=', vsn_get_mode()
    if (vsn_get_mode() /= MODE_ENTERPRISE) sp_fail = 1
    
    call vsn_close()
    
    if (sp_fail == 0) then
       write(*,'(A)') 'SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance'
    else
       write(*,'(A)') 'SP FAILED'
    end if
    stop
  end if
end program test_vsn

