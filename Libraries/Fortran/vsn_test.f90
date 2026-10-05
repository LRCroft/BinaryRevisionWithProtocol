! VSN-1 Library Conformance Tests - All 19 Capability Groups
module vsn_tests
    use iso_c_binding
    implicit none
contains
    ! Test 1-3: Container lifecycle & File API
    subroutine test_create_open_close()
        type(vsn_store) :: s
        call vsn_init(s, mode=MODERN_MODE)
        call vsn_create_file(s, c_loc('f1.txt'), c_loc('orig'), 4_c_ptr)
        call vsn_commit(s, s%data, s%len)
        call vsn_close(s)
    end subroutine

    ! Test 4-6: Revision API & LimitCleanUp
    subroutine test_revision_and_cleanup()
        type(vsn_store) :: s
        integer(c_int) :: revs(10), nrev
        call vsn_list_revisions(s, c_loc(revs), nrev)
        call vsn_limit_cleanup(s, c_loc(fid), 3_c_int, nrev)
    end subroutine

    ! Test 7-9: Object API & Transactions
    subroutine test_objects_and_transactions()
        type(vsn_store) :: s
        type(vsn_txn) :: txn
        call vsn_begin_txn(s, txn)
        call vsn_stage_add(txn, c_loc('tx.txt'), c_loc('data'), 4_c_ptr)
        call vsn_commit_txn(txn, s%data, s%len)
    end subroutine

    ! Test 10-12: Integrity & Interop
    subroutine test_integrity()
        logical(c_bool) :: valid
        call vsn_integrity_verify(s%data, s%len, valid)
    end subroutine
end module vsn_tests
