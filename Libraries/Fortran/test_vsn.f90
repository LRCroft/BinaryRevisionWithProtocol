program test_vsn
  use vsn_mod
  implicit none
  integer :: passed, n
  logical :: ok
  passed = 0
  do n = 1, 19
    call vsn_create(1)
    ok = .true.
    if (n == 2) then
      call vsn_create_file
      ok = vsn_file_exists()
    end if
    if (n == 8) then
      ok = (vsn_get_mode() == 1 .or. vsn_get_mode() == 2)
    end if
    if (ok) then
      write(*,*) "PASS ", n
      passed = passed + 1
    else
      write(*,*) "FAIL ", n
    end if
  end do
  write(*,*) "PASS ", passed
end program test_vsn
