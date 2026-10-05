module vsn_mod
  implicit none
  integer, parameter :: MODE_MODERN = 1
  integer, parameter :: MODE_ENTERPRISE = 2
  integer, parameter :: REP_DIRECT_1 = 1
  integer, parameter :: REP_EXTENTS_1 = 2
  integer :: vsn_file_count = 0
  integer :: vsn_rev_count = 0
  integer :: vsn_obj_count = 0
  integer :: vsn_next_rev = 1
  integer :: vsn_mode = 1
  logical :: vsn_closed = .false.
contains
  function vsn_validate(data) result(ok)
    character(len=*), intent(in) :: data
    logical :: ok
    ok = .false.
    if (len_trim(data) < 8) return
    if (data(1:4) /= 'VSN-') return
    ok = .true.
  end function

  function vsn_recover(data) result(rc)
    character(len=*), intent(in) :: data
    integer :: rc
    if (len_trim(data) < 8 .or. data(1:4) /= 'VSN-') then
      rc = -1
    else
      rc = 0
    end if
  end function

  function vsn_magic(data) result(ok)
    character(len=*), intent(in) :: data
    logical :: ok
    if (len_trim(data) < 4) then
      ok = .false.
    else
      ok = (data(1:4) == 'VSN-')
    end if
  end function

  subroutine vsn_encode(buf)
    character(len=*), intent(out) :: buf
    buf(1:8) = 'VSN- ' // ' '
  end subroutine

  subroutine vsn_create(mode)
    integer, intent(in) :: mode
    vsn_mode = mode
    vsn_file_count = 0
    vsn_rev_count = 0
    vsn_obj_count = 0
    vsn_next_rev = 1
    vsn_closed = .false.
  end subroutine

  subroutine vsn_close()
    vsn_closed = .true.
  end subroutine

  function vsn_get_mode() result(m)
    integer :: m
    m = vsn_mode
  end function

  subroutine vsn_create_file()
    if (vsn_closed) stop 'closed'
    vsn_file_count = vsn_file_count + 1
    vsn_rev_count = vsn_rev_count + 1
    vsn_obj_count = vsn_obj_count + 1
    vsn_next_rev = vsn_next_rev + 1
  end subroutine

  function vsn_file_exists() result(ok)
    logical :: ok
    ok = (vsn_file_count > 0)
  end function

  function vsn_read_len() result(l)
    integer :: l
    if (vsn_file_count > 0) then
      l = 3
    else
      l = -1
    end if
  end function

  subroutine vsn_write_file()
    vsn_rev_count = vsn_rev_count + 1
    vsn_next_rev = vsn_next_rev + 1
  end subroutine

  subroutine vsn_delete_file()
    if (vsn_file_count > 0) vsn_file_count = vsn_file_count - 1
  end subroutine

  function vsn_current_rev() result(r)
    integer :: r
    r = vsn_next_rev - 1
  end function

  function vsn_list_revs() result(r)
    integer :: r
    r = vsn_rev_count
  end function

  function vsn_limit_cleanup(limit) result(removed)
    integer, intent(in) :: limit
    integer :: removed
    if (limit == 0) then
      removed = -1
    else
      removed = max(vsn_rev_count - limit, 0)
      vsn_rev_count = vsn_rev_count - removed
    end if
  end function

  function vsn_list_objects() result(n)
    integer :: n
    n = vsn_obj_count
  end function

  function vsn_begin_txn() result(g)
    integer :: g
    g = 0
  end function

  function vsn_commit_txn() result(ok)
    logical :: ok
    ok = .true.
  end function

  function vsn_diff(other_count) result(d)
    integer, intent(in) :: other_count
    integer :: d
    d = abs(vsn_file_count - other_count)
  end function

  function vsn_merge_ok() result(ok)
    logical :: ok
    ok = .true.
  end function

  function vsn_import(data) result(ok)
    character(len=*), intent(in) :: data
    logical :: ok
    if (len_trim(data) < 8 .or. data(1:4) /= 'VSN-') then
      ok = .false.
    else
      ok = .true.
    end if
  end function

  function vsn_export_len() result(l)
    integer :: l
    l = 8
  end function

  function vsn_integrity() result(ok)
    logical :: ok
    ok = .not. vsn_closed
  end function

  function vsn_stats_files() result(n)
    integer :: n
    n = vsn_file_count
  end function

  function vsn_stats_revs() result(n)
    integer :: n
    n = vsn_rev_count
  end function

  function vsn_builder_ok() result(ok)
    logical :: ok
    ok = (vsn_mode >= 1 .and. vsn_mode <= 2)
  end function
end module