program consumer
  use vsn_mod
  implicit none
  character(len=32) :: buf
  integer :: p, got, i, fails
  logical :: sig
  fails = 0
  do p = 1, 4
    call vsn_create_with_policy(p)       ! store the policy (canonical writer)
    call vsn_encode(buf, 32)             ! wire-out: header + REC_STORAGE_POLICY
    sig = .false.
    do i = 1, 26
      if (ichar(buf(i:i)) == 0 .and. ichar(buf(i+1:i+1)) == 9 .and. &
          ichar(buf(i+2:i+2)) == 4 .and. ichar(buf(i+3:i+3)) == 9 .and. &
          ichar(buf(i+4:i+4)) == 1 .and. ichar(buf(i+5:i+5)) == 1) sig = .true.
    end do
    got = vsn_parse_storage_policy(buf)      ! wire-in: library parser (function)
    if (.not. sig) then
       write(*,'(A,I0)') 'FAIL p=', p, ' wire-out signature missing'
       fails = fails + 1
    end if
    if (got /= p) then
       write(*,'(A,I0,A,I0)') 'FAIL p=', p, ' got=', got
       fails = fails + 1
    end if
  end do
  if (fails == 0) then
     write(*,'(A)') 'CONSUMER FORTRAN PASS'
     stop
  else
     write(*,'(A,I0)') 'CONSUMER FORTRAN FAIL fails=', fails
     stop 1
  end if
end program consumer
