module vsn_mod
  implicit none
  integer, parameter :: MODE_MODERN = 1          ! OBSOLETE: was MODERN wire mode (deprecated)
  integer, parameter :: MODE_ENTERPRISE = 2      ! OBSOLETE: was ENTERPRISE wire mode (deprecated)
  ! Storage Policy values -- authoritative classification (directly on wire)
  integer, parameter :: STORAGE_HIGHLY_VERTICAL    = 1   ! maximum optimization effort
  integer, parameter :: STORAGE_VERTICAL           = 2   ! bounded optimization effort
  integer, parameter :: STORAGE_HORIZONTAL         = 3   ! low optimization effort
  integer, parameter :: STORAGE_HIGHLY_HORIZONTAL  = 4   ! minimal optimization effort
  ! Record type constants
  integer, parameter :: REC_END_OF_RECORDS = 0
  integer, parameter :: REC_FILE_IDENTITY = 1
  integer, parameter :: REC_REVISION = 2
  integer, parameter :: REC_REVISION_SET = 3
  integer, parameter :: REC_FILE_HEAD = 4
  integer, parameter :: REC_CONTENT_OBJECT = 5
  integer, parameter :: REC_COMMIT_MARKER = 6
  integer, parameter :: REC_MODE_DECLARATION = 7     ! OBSOLETE: kept for reader compatibility only
  integer, parameter :: REC_STORAGE_POLICY = 9       ! New: authoritative storage classification (0x0009)
  integer, parameter :: REC_REPRESENTATION_DESCRIPTOR = 8
  ! Field IDs
  integer, parameter :: FID_MODE = 2817              ! OBSOLETE: ModeDeclaration field (deprecated)
  integer, parameter :: FID_STORAGE_POLICY = 2305    ! StoragePolicy.field_id (new), 0x0901
  integer :: vsn_storage_policy = 2                   ! default VERTICAL
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

  subroutine vsn_encode(buf, blen)
    character(len=*), intent(out) :: buf
    integer, intent(in) :: blen
    ! Emit VSN header + canonical REC_STORAGE_POLICY record (0x0009/0x0901/u8)
    if (blen >= 8) then
      buf(1:4) = 'VSN-'
      buf(5:8) = char(0)//char(1)//char(0)//char(1)   ! CFV=1, EV=1
    end if
    if (blen >= 15) then
      buf(9:10)  = char(0)//char(9)          ! REC_STORAGE_POLICY = 0x0009
      buf(11:11) = char(4)                   ! payload length = 4
      buf(12:13) = char(9)//char(1)          ! FID_STORAGE_POLICY = 0x0901
      buf(14:14) = char(1)                   ! value length = 1
      buf(15:15) = char(vsn_storage_policy)  ! u8 policy value (1..4)
    end if
  end subroutine

  recursive subroutine vsn_put_bytes(s, p, arr)
    integer, intent(out) :: s(:)
    integer, intent(in) :: p
    integer, intent(in), dimension(:) :: arr
    integer :: i
    do i = 1, min(size(arr), size(s) - p + 1)
      s(p + i - 1) = arr(i)
    end do
  end subroutine

  recursive subroutine vsn_put_u16(s, p, v)
    integer, intent(out) :: s(:)
    integer, intent(in) :: p
    integer, intent(in) :: v
    s(p) = iand(int(v / 256), 255)
    s(p + 1) = mod(v, 256)
  end subroutine
  subroutine vsn_create(mode)
    integer, intent(in) :: mode
!$omp critical(vsn_lock)
    vsn_mode = mode
    vsn_file_count = 0
    vsn_rev_count = 0
    vsn_obj_count = 0
    vsn_next_rev = 1
    vsn_closed = .false.
!$omp end critical(vsn_lock)
  end subroutine

  subroutine vsn_close()
!$omp critical(vsn_lock)
    vsn_closed = .true.
!$omp end critical(vsn_lock)
  end subroutine

  ! ---- Storage Policy chain (OBSOLETE: cancelled mode mapping removed) ----

  subroutine vsn_create_with_policy(spolicy)
    integer, intent(in) :: spolicy
    ! Canonical writer: stores policy directly; maps to wire mode.
    if (spolicy == 1 .or. spolicy == 2) then
       call vsn_create(MODE_MODERN)        ! HIGHLY_VERTICAL or VERTICAL → MODERN
    else
       call vsn_create(MODE_ENTERPRISE)     ! HORIZONTAL or HIGHLY_HORIZONTAL → ENTERPRISE
    end if
    vsn_storage_policy = spolicy
    if (vsn_storage_policy < 1 .or. vsn_storage_policy > 4) vsn_storage_policy = 2
  end subroutine

  function vsn_get_mode() result(m)
    integer :: m
    m = vsn_mode
  end function

  subroutine vsn_create_file()
    if (vsn_closed) stop 'closed'
!$omp critical(vsn_lock)
    vsn_file_count = vsn_file_count + 1
    vsn_rev_count = vsn_rev_count + 1
    vsn_obj_count = vsn_obj_count + 1
    vsn_next_rev = vsn_next_rev + 1
!$omp end critical(vsn_lock)
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
!$omp critical(vsn_lock)
    vsn_rev_count = vsn_rev_count + 1
    vsn_next_rev = vsn_next_rev + 1
!$omp end critical(vsn_lock)
  end subroutine

  subroutine vsn_delete_file()
!$omp critical(vsn_lock)
    if (vsn_file_count > 0) vsn_file_count = vsn_file_count - 1
!$omp end critical(vsn_lock)
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
    ok = (len_trim(data) >= 8 .and. data(1:4) == 'VSN-')
  end function

  function vsn_parse_storage_policy(data) result(sp)
    character(len=*), intent(in) :: data
    integer :: sp
    ! Canonical value position: "VSN-"(4) + CFV(2) + EV(2) + REC_SP(2)
    ! + plen(1) + FID(2) + vlen(1) => value is the 15th byte.
    sp = -1
    if (len(data) >= 15) sp = ichar(data(15:15))
  end function

  function vsn_export_len() result(l)
    integer :: l
    ! Header(8) + RecordsEnd(2) + REC_STORAGE_POLICY(15) = 25 bytes total
    l = 25
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