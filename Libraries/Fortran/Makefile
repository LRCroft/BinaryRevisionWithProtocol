F90=gfortran all: vsn.o test_vsn.exe%.o: %.f90; $(F90) -c $< -o $@test_vsn.exe: vsn.o; $(F90) vsn.o -o test_vsn.exe clean: rm -f *.o *.exe
