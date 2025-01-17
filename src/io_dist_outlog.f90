! $Id$
!
!  Distributed IO (i.e. each process writes its own file data/procX)
!
!  The file format written by output_snap() (and used, e.g. in var.dat)
!  consists of the followinig Fortran records:
!    1. data(mx,my,mz,nvar)
!    2. t(1), x(mx), y(my), z(mz), dx(1), dy(1), dz(1), deltay(1)
!  Here nvar denotes the number of slots, i.e. 1 for one scalar field, 3
!  for one vector field, 8 for var.dat in the case of MHD with entropy.
!
!  04-nov-11/MR: IOSTAT handling generally introduced
!  16-nov-11/MR: calls to outlog adapted
!  10-Dec-2011/Bourdin.KIS: major cleanup
!
module Io
!
  use Cdata
  use Cparam, only: intlen, fnlen, max_int
  use Messages, only: fatal_error, outlog, warning, svn_id
  use General, only: delete_file
!
  implicit none
!
  include 'io.h'
  include 'record_types.h'
!
  interface write_persist
    module procedure write_persist_logical_0D
    module procedure write_persist_logical_1D
    module procedure write_persist_int_0D
    module procedure write_persist_int_1D
    module procedure write_persist_real_0D
    module procedure write_persist_real_1D
  endinterface
!
  interface read_persist
    module procedure read_persist_logical_0D
    module procedure read_persist_logical_1D
    module procedure read_persist_int_0D
    module procedure read_persist_int_1D
    module procedure read_persist_real_0D
    module procedure read_persist_real_1D
  endinterface
!
  interface read_snap
    module procedure read_snap_double
    module procedure read_snap_single
  endinterface
!
  interface read_globals
    module procedure read_globals_double
    module procedure read_globals_single
  endinterface
!
  interface input_grid
    module procedure input_grid_double
    module procedure input_grid_single
  endinterface
!
  interface input_proc_bounds
    module procedure input_proc_bounds_double
    module procedure input_proc_bounds_single
  endinterface
!
  ! define unique logical unit number for input and output calls
  integer :: lun_input=88
  integer :: lun_output=91
!
  ! Indicates if IO is done distributed (each proc writes into a procdir)
  ! or collectively (eg. by specialized IO-nodes or by MPI-IO).
  logical :: lcollective_IO=.false.
  character (len=labellen) :: IO_strategy="dist"
!
  logical :: persist_initialized=.false.
  integer :: persist_last_id=-max_int
!
  contains
!***********************************************************************
    subroutine register_io
!
!  dummy routine, generates separate directory for each processor.
!  VAR#-files are written to the directory directory_snap which will
!  be the same as directory, unless specified otherwise.
!
!  20-sep-02/wolf: coded
!
      use Mpicomm, only: lroot
!
!  identify version number
!
      if (lroot) call svn_id("$Id$")
      ldistribute_persist = .true.
!
    endsubroutine register_io
!***********************************************************************
    subroutine directory_names
!
!  Set up the directory names:
!  set directory name for the output (one subdirectory for each processor)
!  if datadir_snap (where var.dat, VAR# go) is empty, initialize to datadir
!
!  02-oct-2002/wolf: coded
!
      use General, only: directory_names_std
!
!  check whether directory_snap contains `/proc0' -- if so, revert to the
!  default name.
!  Rationale: if directory_snap was not explicitly set in start.in, it
!  will be written to param.nml as 'data/proc0', but this should in fact
!  be data/procN on processor N.
!
      if ((datadir_snap == '') .or. (index(datadir_snap,'proc0')>0)) &
        datadir_snap = datadir
!
      call directory_names_std(.true.)
!
    endsubroutine directory_names
!***********************************************************************
    subroutine output_snap(a,nv,file)
!
!  Write snapshot file, always write time and mesh, could add other things.
!
!  11-apr-97/axel: coded
!  13-Dec-2011/Bourdin.KIS: reworked
!  13-feb-2014/MR: made 'file' optional, 'a' assumed-shape (for downsampled output);
!                  moved donwsampling stuff to snapshot
!
      use Mpicomm, only: start_serialize, end_serialize
      use General, only: get_range_no
!
      character (len=*), intent(in), optional :: file
      integer, intent(in) :: nv
      real, dimension (:,:,:,:), intent(in) :: a
!
      real :: t_sp   ! t in single precision for backwards compatibility
      integer :: io_err
      logical :: lerror
!
      t_sp = t
      if (lroot .and. (ip <= 8)) print *, 'output_vect: nv =', nv
!
      if (lserial_io) call start_serialize
      if (present(file)) then
        call delete_file(trim(directory_snap)//'/'//file)
        open (lun_output, FILE=trim(directory_snap)//'/'//file, FORM='unformatted', IOSTAT=io_err, status='new')
        lerror = outlog (io_err, 'openw', file, dist=lun_output, location='output_snap')
      endif
!
      if (lwrite_2d) then
        if (nx == 1) then
          write (lun_output, IOSTAT=io_err) a(l1,:,:,:)
        elseif (ny == 1) then
          write (lun_output, IOSTAT=io_err) a(:,m1,:,:)
        elseif (nz == 1) then
          write (lun_output, IOSTAT=io_err) a(:,:,n1,:)
        else
          io_err = 0
          call fatal_error ('output_snap', 'lwrite_2d used for 3D simulation!')
        endif
      elseif (ldownsampl) then
        write (lun_output, IOSTAT=io_err) a(firstind(1):l2:downsampl(1), &
                                            firstind(2):m2:downsampl(2), &
                                            firstind(3):n2:downsampl(3), :)
      else
        write (lun_output, IOSTAT=io_err) a
      endif
!
      lerror = outlog(io_err, 'main data')
!
!  Write shear at the end of x,y,z,dx,dy,dz.
!  At some good moment we may want to treat deltay like with
!  other modules and call a corresponding i/o parameter module.
!
      if (lshear) then
        write (lun_output, IOSTAT=io_err) t_sp, x, y, z, dx, dy, dz, deltay
        lerror = outlog(io_err, 'additional data and deltay')
      else
        write (lun_output, IOSTAT=io_err) t_sp, x, y, z, dx, dy, dz
        lerror = outlog(io_err, 'additional data')
      endif
!
      if (lserial_io) call end_serialize
!
    endsubroutine output_snap
!***********************************************************************
    subroutine output_snap_finalize
!
!  Close snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: adapted from output_snap
!
      use Mpicomm, only: end_serialize
!
      integer :: io_err
      logical :: lerror
!
      if (persist_initialized) then
        write (lun_output, iostat=io_err) id_block_PERSISTENT
        lerror = outlog (io_err, 'id_block_PERSISTENT')
        persist_initialized = .false.
        persist_last_id = -max_int
      endif
!
      close (lun_output)
!
      if (lserial_io) call end_serialize
!
    endsubroutine output_snap_finalize
!***********************************************************************
    subroutine fseek_pos(unit, rec_len, num_rec, reference)
!
!  Non-functional dummy routine.
!
!  25-Apr-2012/Bourdin.KIS: coded
!
      use General, only: itoa
!
      integer, intent(in) :: unit
      integer(kind=8), intent(in) :: rec_len, num_rec
      integer, intent(in) :: reference
!
      if (lroot) write (*,*) 'fseek_pos:', unit, rec_len, num_rec, reference
      call fatal_error ('fseek_pos on unit '//trim (itoa (unit)), &
          "not available for the distributed IO module.", .true.)
!
    endsubroutine fseek_pos
!***********************************************************************
    logical function init_write_persist(file)
!
!  Initialize writing of persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in), optional :: file
!
      character (len=fnlen), save :: filename=""
      integer :: io_err
!
      persist_last_id = -max_int
      init_write_persist = .false.
!
      if (present (file)) then
        filename = file
        persist_initialized = .false.
        return
      endif
!
      if (filename /= "") then
        close (lun_output)
        call delete_file(trim (directory_snap)//'/'//file)
        open (lun_output, FILE=trim (directory_snap)//'/'//file, FORM='unformatted', &
              IOSTAT=io_err, status='new')
        init_write_persist = outlog (io_err, 'openw persistent file', &
                             trim (directory_snap)//'/'//file, location='init_write_persist' )
        filename = ""
      endif
!
      if (lroot .and. (ip <= 9)) write (*,*) 'begin persistent block'
      write (lun_output, iostat=io_err) id_block_PERSISTENT
      init_write_persist = outlog (io_err, 'id_block_PERSISTENT')
      persist_initialized = .not. init_write_persist
!
    endfunction init_write_persist
!***********************************************************************
    logical function write_persist_id(label, id)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
!
      integer :: io_err
!
      write_persist_id = .true.
      if (.not. persist_initialized) write_persist_id = init_write_persist()
      if (.not. persist_initialized) return
!
      if (persist_last_id /= id) then
        write (lun_output, iostat=io_err) id
        write_persist_id = outlog (io_err, 'persistent ID '//label)
        persist_last_id = id
      else
        write_persist_id = .false.
      endif
!
    endfunction write_persist_id
!***********************************************************************
    logical function write_persist_logical_0D(label, id, value)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
      logical, intent(in) :: value
!
      integer :: io_err
!
      write_persist_logical_0D = .true.
      if (write_persist_id (label, id)) return
!
      write (lun_output, iostat=io_err) value
      write_persist_logical_0D = outlog (io_err, 'persistent '//label)
!
    endfunction write_persist_logical_0D
!***********************************************************************
    logical function write_persist_logical_1D(label, id, value)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
      logical, dimension(:), intent(in) :: value
!
      integer :: io_err
!
      write_persist_logical_1D = .true.
      if (write_persist_id (label, id)) return
!
      write (lun_output, iostat=io_err) value
      write_persist_logical_1D = outlog (io_err, 'persistent '//label)
!
    endfunction write_persist_logical_1D
!***********************************************************************
    logical function write_persist_int_0D(label, id, value)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
      integer, intent(in) :: value
!
      integer :: io_err
!
      write_persist_int_0D = .true.
      if (.not. persist_initialized) return
      if (write_persist_id (label, id)) return
!
      write (lun_output, iostat=io_err) value
      write_persist_int_0D = outlog (io_err, 'persistent '//label)
!
    endfunction write_persist_int_0D
!***********************************************************************
    logical function write_persist_int_1D(label, id, value)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
      integer, dimension(:), intent(in) :: value
!
      integer :: io_err
!
      write_persist_int_1D = .true.
      if (write_persist_id (label, id)) return
!
      write (lun_output, iostat=io_err) value
      write_persist_int_1D = outlog (io_err, 'persistent '//label)
!
    endfunction write_persist_int_1D
!***********************************************************************
    logical function write_persist_real_0D(label, id, value)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
      real, intent(in) :: value
!
      integer :: io_err
!
      write_persist_real_0D = .true.
      if (write_persist_id (label, id)) return
!
      write (lun_output, iostat=io_err) value
      write_persist_real_0D = outlog (io_err, 'persistent '//label)
!
    endfunction write_persist_real_0D
!***********************************************************************
    logical function write_persist_real_1D(label, id, value)
!
!  Write persistent data to snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(in) :: id
      real, dimension(:), intent(in) :: value
!
      integer :: io_err
!
      write_persist_real_1D = .true.
      if (write_persist_id (label, id)) return
!
      write (lun_output, iostat=io_err) value
      write_persist_real_1D = outlog (io_err, 'persistent '//label)
!
    endfunction write_persist_real_1D
!***********************************************************************
    subroutine input_snap(file,a,nv,mode)
!
!  manages reading of snapshot from different precision
!
!  24-oct-13/MR: coded
!
      character (len=*), intent(in) :: file
      integer, intent(in) :: nv, mode
      real, dimension (mx,my,mz,nv), intent(out) :: a

      real(KIND=rkind8), dimension(:,:,:,:), allocatable :: adb
      real(KIND=rkind4), dimension(:,:,:,:), allocatable :: asg

      real(KIND=rkind8), dimension(:), allocatable :: xdb,ydb,zdb
      real(KIND=rkind4), dimension(:), allocatable :: xsg,ysg,zsg

      real(KIND=rkind8) :: dxdb,dydb,dzdb,deltaydb
      real(KIND=rkind4) :: dxsg,dysg,dzsg,deltaysg

      if (lread_from_other_prec) then
        if (kind(a)==rkind4) then
          allocate(adb(mx,my,mz,nv),xdb(mx),ydb(my),zdb(mz))
          call read_snap(file,adb,xdb,ydb,zdb,dxdb,dydb,dzdb,deltaydb,nv,mode)
          a=adb; x=xdb; y=ydb; z=zdb; dx=dxdb; dy=dydb; dz=dzdb; deltay=deltaydb
        elseif (kind(a)==rkind8) then
          allocate(asg(mx,my,mz,nv),xsg(mx),ysg(my),zsg(mz))
          call read_snap(file,asg,xsg,ysg,zsg,dxsg,dysg,dzsg,deltaysg,nv,mode)
          a=asg; x=xsg; y=ysg; z=zsg; dx=dxsg; dy=dysg; dz=dzsg; deltay=deltaysg
        endif
      else
        call read_snap(file,a,x,y,z,dx,dy,dz,deltay,nv,mode)
      endif

    endsubroutine input_snap
!***********************************************************************
    subroutine read_snap_single(file,a,x,y,z,dx,dy,dz,deltay,nv,mode)
!
!  Read snapshot file in single precision, possibly with mesh and time (if mode=1).
!
!  24-oct-13/MR: derived from input_snap
!  28-oct-13/MR: consistency check for t_sp relaxed for restart from different precision
!   6-mar-14/MR: if timestamp of snapshot inconsistent, now three choices:
!                if lreset_tstart=F: cancel program
!                                =T, tstart unspecified: use minimum time of all
!                                var.dat 
!                                                        for start
!                                 T, tstart specified: use this value
!
      use Mpicomm, only: start_serialize, end_serialize, mpibcast_real, mpiallreduce_or, &
                         stop_it, mpiallreduce_min_sgl, MPI_COMM_WORLD
!
      character (len=*), intent(in) :: file
      integer, intent(in) :: nv, mode
      real(KIND=rkind4), dimension (mx,my,mz,nv), intent(out) :: a
!
      real(KIND=rkind4) :: t_sp, t_sgl

      real(KIND=rkind4),                 intent(out) :: dx, dy, dz, deltay
      real(KIND=rkind4), dimension (mx), intent(out) :: x
      real(KIND=rkind4), dimension (my), intent(out) :: y
      real(KIND=rkind4), dimension (mz), intent(out) :: z

      real :: t_test   ! t in single precision for backwards compatibility

      integer :: io_err
      logical :: lerror, ltest
!
      if (lserial_io) call start_serialize
      open (lun_input, FILE=trim(directory_snap)//'/'//file, FORM='unformatted', &
            IOSTAT=io_err, status='old')
      lerror = outlog (io_err, "openr snapshot data", trim(directory_snap)//'/'//file, &
                       location='read_snap_single')
!      if (ip<=8) print *, 'read_snap_single: open, mx,my,mz,nv=', mx, my, mz, nv
      if (lwrite_2d) then
        if (nx == 1) then
          read (lun_input, IOSTAT=io_err) a(4,:,:,:)
        elseif (ny == 1) then
          read (lun_input, IOSTAT=io_err) a(:,4,:,:)
        elseif (nz == 1) then
          read (lun_input, IOSTAT=io_err) a(:,:,4,:)
        else
          io_err = 0
          call fatal_error ('read_snap_single', 'lwrite_2d used for 3-D simulation!')
        endif
      else
!
!  Possibility of reading data with different numbers of ghost zones.
!  In that case, one must regenerate the mesh with luse_oldgrid=T.
!
        if (nghost_read_fewer==0) then
          read (lun_input, IOSTAT=io_err) a
        elseif (nghost_read_fewer>0) then
          read (lun_input, IOSTAT=io_err) &
              a(1+nghost_read_fewer:mx-nghost_read_fewer, &
                1+nghost_read_fewer:my-nghost_read_fewer, &
                1+nghost_read_fewer:mz-nghost_read_fewer,:)
!
!  The following 3 possibilities allow us to replicate 1-D data input
!  in x (nghost_read_fewer=-1), y (-2), or z (-3) correspondingly.
!
        elseif (nghost_read_fewer==-1) then
          read (lun_input, IOSTAT=io_err) a(:,1:1+nghost*2,1:1+nghost*2,:)
          a=spread(spread(a(:,m1,n1,:),2,my),3,mz)
        elseif (nghost_read_fewer==-2) then
          read (lun_input, IOSTAT=io_err) a(1:1+nghost*2,:,1:1+nghost*2,:)
          a=spread(spread(a(l1,:,n1,:),1,mx),3,mz)
        elseif (nghost_read_fewer==-3) then
          read (lun_input, IOSTAT=io_err) a(1:1+nghost*2,1:1+nghost*2,:,:)
          a=spread(spread(a(l1,m1,:,:),1,mx),2,my)
        else
          call fatal_error('read_snap_single','nghost_read_fewer must be >=0')
        endif
      endif
      lerror = outlog (io_err, 'main data')

      if (ip <= 8) print *, 'read_snap_single: read ', file
      if (mode == 1) then
!
!  Check whether we want to read deltay from snapshot.
!
        if (lshear) then
          read (lun_input, IOSTAT=io_err) t_sp, x, y, z, dx, dy, dz, deltay
          lerror = outlog (io_err, 'additional data + deltay')
        else
          if (nghost_read_fewer==0) then
            read (lun_input, IOSTAT=io_err) t_sp, x, y, z, dx, dy, dz
          elseif (nghost_read_fewer>0) then
            read (lun_input, IOSTAT=io_err) t_sp
          endif
          lerror = outlog (io_err, 'additional data')
        endif
!
!  Verify consistency of the snapshots regarding their timestamp,
!  unless lreset_tstart=T, in which case we reset all times to tstart.
!
        if (.not.lreset_tstart.or.tstart==impossible) then
!
          t_test = t_sp
          call mpibcast_real(t_test,comm=MPI_COMM_WORLD)
          call mpiallreduce_or(t_test /= t_sp .and. .not.lread_from_other_prec &
                               .or. abs(t_test-t_sp)>1.e-6,ltest,MPI_COMM_WORLD)
!
!  If timestamps deviate at any processor
!
          if (ltest) then
            if (lreset_tstart) then
!
!  If reset of tstart enabled and tstart unspecified, use minimum of all t_sp
!
              call mpiallreduce_min_sgl(t_sp,t_sgl,MPI_COMM_WORLD)
              tstart=t_sgl
              if (lroot) write (*,*) 'Timestamps in snapshot INCONSISTENT. Using t=', tstart,'.'
            else
              write (*,*) 'ERROR: '//trim(directory_snap)//'/'//trim(file)// &
                          ' IS INCONSISTENT: t=', t_sp
              call stop_it('read_snap_single')
            endif
          else
            tstart=t_sp
          endif
!
        endif
!
!  Set time or overwrite it by a given value.
!
        if (lreset_tstart) then
          t = tstart
        else
          t = t_sp
        endif
!
!  Verify the read values for x, y, z, and t.
!
        if (ip <= 3) print *, 'read_snap_single: x=', x
        if (ip <= 3) print *, 'read_snap_single: y=', y
        if (ip <= 3) print *, 'read_snap_single: z=', z
        if (ip <= 3) print *, 'read_snap_single: t=', t
!
      endif
!
    endsubroutine read_snap_single
!***********************************************************************
    subroutine read_snap_double(file,a,x,y,z,dx,dy,dz,deltay,nv,mode)
!
!  Read snapshot file in double precision, possibly with mesh and time (if mode=1).
!
!  24-oct-13/MR: derived from input_snap
!  28-oct-13/MR: consistency check for t_sp relaxed for restart from different precision
!   6-mar-14/MR: if timestamp of snapshot inconsistent, now three choices:
!                if lreset_tstart=F: cancel program
!                                =T, tstart unspecified: use minimum time of all var.dat 
!                                                        for start
!                                =T, tstart specified: use this value
!                             
      use Mpicomm, only: start_serialize, end_serialize, mpibcast_real, mpiallreduce_or, &
                         stop_it, mpiallreduce_min_dbl, MPI_COMM_WORLD
!
      character (len=*), intent(in) :: file
      integer, intent(in) :: nv, mode
      real(KIND=rkind8), dimension (mx,my,mz,nv), intent(out) :: a
!
      real(KIND=rkind8) :: t_sp, t_dbl

      real(KIND=rkind8), intent(out) :: dx, dy, dz, deltay
      real(KIND=rkind8), dimension (mx), intent(out) :: x
      real(KIND=rkind8), dimension (my), intent(out) :: y
      real(KIND=rkind8), dimension (mz), intent(out) :: z

      real :: t_test   ! t in single precision for backwards compatibility
      integer :: io_err
      logical :: lerror,ltest
!
      if (lserial_io) call start_serialize
      open (lun_input, FILE=trim(directory_snap)//'/'//file, FORM='unformatted', &
            IOSTAT=io_err, status='old')
      lerror = outlog (io_err, "openr snapshot data", trim(directory_snap)//'/'//file, &
                       location='read_snap_double')
!      if (ip<=8) print *, 'read_snap_double: open, mx,my,mz,nv=', mx, my, mz, nv
      if (lwrite_2d) then
        if (nx == 1) then
          read (lun_input, IOSTAT=io_err) a(4,:,:,:)
        elseif (ny == 1) then
          read (lun_input, IOSTAT=io_err) a(:,4,:,:)
        elseif (nz == 1) then
          read (lun_input, IOSTAT=io_err) a(:,:,4,:)
        else
          io_err = 0
          call fatal_error ('read_snap_double', 'lwrite_2d used for 3-D simulation!')
        endif
      else
!
!  Possibility of reading data with different numbers of ghost zones.
!  In that case, one must regenerate the mesh with luse_oldgrid=T.
!
        if (nghost_read_fewer==0) then
          read (lun_input, IOSTAT=io_err) a
        elseif (nghost_read_fewer>0) then
          read (lun_input, IOSTAT=io_err) &
              a(1+nghost_read_fewer:mx-nghost_read_fewer, &
                1+nghost_read_fewer:my-nghost_read_fewer, &
                1+nghost_read_fewer:mz-nghost_read_fewer,:)
!
!  The following 3 possibilities allow us to replicate 1-D data input
!  in x (nghost_read_fewer=-1), y (-2), or z (-3) correspondingly.
!
        elseif (nghost_read_fewer==-1) then
          read (lun_input, IOSTAT=io_err) a(:,1:1+nghost*2,1:1+nghost*2,:)
          a=spread(spread(a(:,m1,n1,:),2,my),3,mz)
        elseif (nghost_read_fewer==-2) then
          read (lun_input, IOSTAT=io_err) a(1:1+nghost*2,:,1:1+nghost*2,:)
          a=spread(spread(a(l1,:,n1,:),1,mx),3,mz)
        elseif (nghost_read_fewer==-3) then
          read (lun_input, IOSTAT=io_err) a(1:1+nghost*2,1:1+nghost*2,:,:)
          a=spread(spread(a(l1,m1,:,:),1,mx),2,my)
        else
          call fatal_error('read_snap_double','nghost_read_fewer must be >=0')
        endif
      endif
      lerror = outlog (io_err, 'main data')

      if (ip <= 8) print *, 'read_snap: read ', file
      if (mode == 1) then
!
!  Check whether we want to read deltay from snapshot.
!
        if (lshear) then
          read (lun_input, IOSTAT=io_err) t_sp, x, y, z, dx, dy, dz, deltay
          lerror = outlog (io_err, 'additional data + deltay')
        else
          if (nghost_read_fewer==0) then
            read (lun_input, IOSTAT=io_err) t_sp, x, y, z, dx, dy, dz
          elseif (nghost_read_fewer>0) then
            read (lun_input, IOSTAT=io_err) t_sp
          endif
          lerror = outlog (io_err, 'additional data')
        endif
!
!  Verify consistency of the snapshots regarding their timestamp,
!  unless lreset_tstart=T, in which case we reset all times to tstart.
!
        if (.not.lreset_tstart.or.tstart==impossible) then
!
          t_test = t_sp
          call mpibcast_real(t_test,comm=MPI_COMM_WORLD)
          call mpiallreduce_or(t_test /= t_sp .and. .not.lread_from_other_prec &
                               .or. abs(t_test-t_sp)>1.e-6,ltest,MPI_COMM_WORLD)
!
!  If timestamp deviates at any processor
!
          if (ltest) then
            if (lreset_tstart) then
!
!  If reset of tstart enabled and tstart unspecified, use minimum of all t_sp
!
              call mpiallreduce_min_dbl(t_sp,t_dbl,MPI_COMM_WORLD)
              tstart=t_dbl
              if (lroot) write (*,*) 'Timestamps in snapshot INCONSISTENT. Using t=', tstart, '.'
            else
              write (*,*) 'ERROR: '//trim(directory_snap)//'/'//trim(file)// &
                          ' IS INCONSISTENT: t=', t_sp
              call stop_it('read_snap_double')
            endif
          else
            tstart=t_sp
          endif
!
        endif
!
!  Set time or overwrite it by a given value.
!
        if (lreset_tstart) then
          t = tstart
        else
          t = t_sp
        endif
!
!  Verify the read values for x, y, z, and t.
!
        if (ip <= 3) print *, 'read_snap_double: x=', x
        if (ip <= 3) print *, 'read_snap_double: y=', y
        if (ip <= 3) print *, 'read_snap_double: z=', z
        if (ip <= 3) print *, 'read_snap_double: t=', t
!
      endif
!
    endsubroutine read_snap_double
!***********************************************************************
    subroutine input_snap_finalize
!
!  Close snapshot file.
!
!  11-apr-97/axel: coded
!  13-Dec-2011/Bourdin.KIS: reworked
!
      use Mpicomm, only: end_serialize
!
      close (lun_input)
      if (lserial_io) call end_serialize
!
    endsubroutine input_snap_finalize
!***********************************************************************
    logical function init_read_persist(file)
!
!  Initialize writing of persistent data to persistent file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      use Mpicomm, only: mpibcast_logical, MPI_COMM_WORLD
      use General, only: file_exists
!
      character (len=*), intent(in), optional :: file
!
      integer :: io_err
!
      init_read_persist = .true.
!
      if (present (file)) then
        if (lroot) init_read_persist = .not. file_exists (trim (directory_snap)//'/'//file)
        call mpibcast_logical (init_read_persist,comm=MPI_COMM_WORLD)
        if (init_read_persist) return
      endif
!
      if (present (file)) then
        close (lun_input)
        open (lun_input, FILE=trim (directory_snap)//'/'//file, FORM='unformatted', IOSTAT=io_err, status='old')
        init_read_persist = outlog (io_err, 'openr persistent data',file,location='init_read_persist')
      endif
!
      if (lroot .and. (ip <= 9)) write (*,*) 'begin persistent block'
      init_read_persist = .false.
      persist_initialized = .true.
!
    endfunction init_read_persist
!***********************************************************************
    logical function read_persist_id(label, id, lerror_prone)
!
!  Read persistent block ID from snapshot file.
!
!  17-Feb-2012/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(out) :: id
      logical, intent(in), optional :: lerror_prone
!
      logical :: lcatch_error
      integer :: io_err
!
      lcatch_error = .false.
      if (present (lerror_prone)) lcatch_error = lerror_prone
!
      read (lun_input, iostat=io_err) id
      if (lcatch_error) then
        if (io_err /= 0) then
          id = -max_int
          read_persist_id = .true.
        else
          read_persist_id = .false.
        endif
      else
        read_persist_id = outlog (io_err, 'persistent ID '//label,lcont=.true.)
      endif
!
    endfunction read_persist_id
!***********************************************************************
    logical function read_persist_logical_0D(label, value)
!
!  Read persistent data from snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      logical, intent(out) :: value
!
      integer :: io_err
!
      read (lun_input, iostat=io_err) value
      read_persist_logical_0D = outlog(io_err, 'persistent '//label,lcont=.true.)
!
    endfunction read_persist_logical_0D
!***********************************************************************
    logical function read_persist_logical_1D(label, value)
!
!  Read persistent data from snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      logical, dimension(:), intent(out) :: value
!
      integer :: io_err
!
      read (lun_input, iostat=io_err) value
      read_persist_logical_1D = outlog(io_err, 'persistent '//label,lcont=.true.)
!
    endfunction read_persist_logical_1D
!***********************************************************************
    logical function read_persist_int_0D(label, value)
!
!  Read persistent data from snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, intent(out) :: value
!
      integer :: io_err
!
      read (lun_input, iostat=io_err) value
      read_persist_int_0D = outlog(io_err, 'persistent '//label,lcont=.true.)
!
    endfunction read_persist_int_0D
!***********************************************************************
    logical function read_persist_int_1D(label, value)
!
!  Read persistent data from snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!
      character (len=*), intent(in) :: label
      integer, dimension(:), intent(out) :: value
!
      integer :: io_err
!
      read (lun_input, iostat=io_err) value
      read_persist_int_1D = outlog(io_err, 'persistent '//label,lcont=.true.)
!
    endfunction read_persist_int_1D
!***********************************************************************
    logical function read_persist_real_0D(label, value)
!
!  Read persistent data from snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!  23-oct-2013/MR: modified for reading of different precision
!
      character (len=*), intent(in) :: label
      real, intent(out) :: value
!
      integer :: io_err
      real(KIND=rkind8) :: vdb
      real(KIND=rkind4) :: vsg
!
      if (lread_from_other_prec) then
        if (kind(value)==rkind4) then
          read (lun_input, iostat=io_err) vdb
          value=vdb
        elseif (kind(value)==rkind8) then
          read (lun_input, iostat=io_err) vsg
          value=vsg
        endif
      else
        read (lun_input, iostat=io_err) value
      endif

      read_persist_real_0D = outlog(io_err, 'persistent '//label,lcont=.true.)
!
    endfunction read_persist_real_0D
!***********************************************************************
    logical function read_persist_real_1D(label, value)
!
!  Read persistent data from snapshot file.
!
!  13-Dec-2011/Bourdin.KIS: coded
!  23-oct-2013/MR: modified for reading of different precision
!
      character (len=*), intent(in) :: label
      real, dimension(:), intent(out) :: value
!
      integer :: io_err
      real(KIND=rkind8), dimension(:), allocatable :: vdb
      real(KIND=rkind4), dimension(:), allocatable :: vsg
!
      if (lread_from_other_prec) then
        if (kind(value)==rkind4) then
          allocate(vdb(size(value)))
          read (lun_input, iostat=io_err) vdb
          value=vdb
        elseif (kind(value)==rkind8) then
          allocate(vsg(size(value)))
          read (lun_input, iostat=io_err) vsg
          value=vsg
        endif
      else
        read (lun_input, iostat=io_err) value
      endif
!
      read_persist_real_1D = outlog(io_err, 'persistent '//label, lcont=.true.)
!
    endfunction read_persist_real_1D
!***********************************************************************
    subroutine output_globals(file,a,nv)
!
!  Write snapshot file of globals, ignoring mesh.
!
!  10-nov-06/tony: coded
!
      use Mpicomm, only: start_serialize, end_serialize
!
      integer :: nv
      real, dimension (mx,my,mz,nv) :: a
      character (len=*) :: file
!
      integer :: io_err
      logical :: lerror
!
      if (lserial_io) call start_serialize
      open(lun_output,FILE=trim(directory_snap)//'/'//file,FORM='unformatted',IOSTAT=io_err,status='replace')
      lerror = outlog(io_err,"openw",file,location='output_globals')
!
      if (lwrite_2d) then
        if (nx==1) then
          write(lun_output,IOSTAT=io_err) a(4,:,:,:)
        elseif (ny==1) then
          write(lun_output,IOSTAT=io_err) a(:,4,:,:)
        elseif (nz==1) then
          write(lun_output,IOSTAT=io_err) a(:,:,4,:)
        else
          io_err=0
          call fatal_error('output_globals','lwrite_2d used for 3-D simulation!')
        endif
      else
        write(lun_output,IOSTAT=io_err) a
      endif
      lerror = outlog(io_err,"data block")
      close(lun_output)
!
      if (lserial_io) call end_serialize
!
    endsubroutine output_globals
!***********************************************************************
    subroutine input_globals(file,a,nv)
!
!  Read globals snapshot file, ignoring mesh.
!
!  10-nov-06/tony: coded
!
      use Mpicomm, only: start_serialize,end_serialize
!
      character (len=*) :: file
      integer :: nv
      real, dimension (mx,my,mz,nv) :: a
!
      integer :: io_err
      logical :: lerror
      real(KIND=rkind8), dimension(:,:,:,:), allocatable :: adb
      real(KIND=rkind4), dimension(:,:,:,:), allocatable :: asg

!
      if (lserial_io) call start_serialize
!
      open(lun_input,FILE=trim(directory_snap)//'/'//file,FORM='unformatted',IOSTAT=io_err,status='old')
      lerror = outlog(io_err,"openr globals",file,location='input_globals')

      if (lread_from_other_prec) then
        if (kind(a)==rkind4) then
          allocate(adb(mx,my,mz,nv))
          call read_globals(adb)
          a=adb
        elseif (kind(a)==rkind8) then
          allocate(asg(mx,my,mz,nv))
          call read_globals(asg)
          a=asg
        endif
      else
        call read_globals(a)
      endif

      close(lun_input)
!
      if (lserial_io) call end_serialize
!
    endsubroutine input_globals
!***********************************************************************
    subroutine read_globals_double(a)
!
!  Read globals snapshot file in double precision
!
!  23-oct-13/MR  : derived from input_globals
!
      real(KIND=rkind8), dimension (:,:,:,:) :: a
!
      integer :: io_err
      logical :: lerror

      if (lwrite_2d) then
        if (nx==1) then
          read(lun_input,IOSTAT=io_err) a(4,:,:,:)
        elseif (ny==1) then
          read(lun_input,IOSTAT=io_err) a(:,4,:,:)
        elseif (nz==1) then
          read(lun_input,IOSTAT=io_err) a(:,:,4,:)
        else
          io_err=0
          call fatal_error('input_globals','lwrite_2d used for 3-D simulation!')
        endif
      else
        read(lun_input,IOSTAT=io_err) a
      endif
      lerror = outlog(io_err,"data block",location='read_globals_double')
!
    endsubroutine read_globals_double
!***********************************************************************
    subroutine read_globals_single(a)
!
!  Read globals snapshot file in single precision
!
!  23-oct-13/MR  : derived from input_globals
!
      real(KIND=rkind4), dimension (:,:,:,:) :: a
!
      integer :: io_err
      logical :: lerror

      if (lwrite_2d) then
        if (nx==1) then
          read(lun_input,IOSTAT=io_err) a(4,:,:,:)
        elseif (ny==1) then
          read(lun_input,IOSTAT=io_err) a(:,4,:,:)
        elseif (nz==1) then
          read(lun_input,IOSTAT=io_err) a(:,:,4,:)
        else
          io_err=0
          call fatal_error('input_globals','lwrite_2d used for 3-D simulation!')
        endif
      else
        read(lun_input,IOSTAT=io_err) a
      endif
      lerror = outlog(io_err,"data block",location='read_globals_single')
!
    endsubroutine read_globals_single
!***********************************************************************
    subroutine log_filename_to_file(file,flist)
!
!  In the directory containing `filename', append one line to file
!  `flist' containing the file part of filename
!
      use General, only: parse_filename, safe_character_assign
!
      character (len=*) :: file,flist
!
      character (len=fnlen) :: dir,fpart
      integer :: io_err
      logical :: lerror
!
      call parse_filename(file,dir,fpart)
      if (dir == '.') call safe_character_assign(dir,directory_snap)
!
      open(lun_output,FILE=trim(dir)//'/'//flist,POSITION='append',IOSTAT=io_err)
      ! file not distributed?, backskipping enabled
      lerror = outlog(io_err,"openw",trim(dir)//'/'//flist,dist=-lun_output, &
                      location='log_filename_to_file')
      write(lun_output,'(A)',IOSTAT=io_err) trim(fpart)
      lerror = outlog(io_err,"fpart", trim(dir)//'/'//flist)
      close(lun_output)
!
      if (lcopysnapshots_exp) then
        if (lroot) then
          open(lun_output,FILE=trim(datadir)//'/move-me.list',POSITION='append',IOSTAT=io_err)
          ! file not distributed?, backskipping enabled
          lerror = outlog(io_err,"openw",trim(datadir)//'/move-me.list',dist=-lun_output, &
                          location='log_filename_to_file')
          write(lun_output,'(A)',IOSTAT=io_err) trim(fpart)
          lerror = outlog(io_err,"fpart")
          close(lun_output)
        endif
      endif
!
    endsubroutine log_filename_to_file
!***********************************************************************
    subroutine wgrid(file,mxout,myout,mzout)
!
!  Write processor-local part of grid coordinates.
!
!  21-jan-02/wolf: coded
!  15-jun-03/axel: Lx,Ly,Lz are now written to file (Tony noticed the mistake)
!  30-sep-13/MR  : optional parameters mxout,myout,mzout added
!                  to be able to output coordinate vectors with coordinates differing from
!                  mx,my,mz

      character (len=*) :: file
      integer, optional :: mxout,myout,mzout
!
      integer           :: mxout1,myout1,mzout1
      integer :: io_err
      logical :: lerror
      real :: t_sp   ! t in single precision for backwards compatibility
!
     if (present(mzout)) then
        mxout1=mxout
        myout1=myout
        mzout1=mzout
      else
        mxout1=mx
        myout1=my
        mzout1=mz
      endif
!
      t_sp = t

      open(lun_output,FILE=trim(directory)//'/'//file,FORM='unformatted',IOSTAT=io_err,status='replace')
      if (io_err /= 0) call fatal_error('wgrid', &
          "Cannot open " // trim(file) // " (or similar) for writing" // &
          " -- is data/ visible from all nodes?", .true.)
      lerror = outlog(io_err,"openw",trim(directory)//'/'//file,location='wgrid')
      write(lun_output,IOSTAT=io_err) t_sp,x(1:mxout1),y(1:myout1),z(1:mzout1),dx,dy,dz
      lerror = outlog(io_err,"main data block")
      write(lun_output,IOSTAT=io_err) dx,dy,dz
      lerror = outlog(io_err,"dx,dy,dz")
      write(lun_output,IOSTAT=io_err) Lx,Ly,Lz
      lerror = outlog(io_err,"Lx,Ly,Lz")
      write(lun_output,IOSTAT=io_err) dx_1(1:mxout1),dy_1(1:myout1),dz_1(1:mzout1)
      lerror = outlog(io_err,"dx_1,dy_1,dz_1")
      write(lun_output,IOSTAT=io_err) dx_tilde(1:mxout1),dy_tilde(1:myout1),dz_tilde(1:mzout1)
      lerror = outlog(io_err,"dx_tilde,dy_tilde,dz_tilde")
      close(lun_output,IOSTAT=io_err)
      lerror = outlog(io_err,'close')
!
    endsubroutine wgrid
!***********************************************************************
    subroutine input_grid_single(x,y,z,dx,dy,dz,Lx,Ly,Lz,dx_1,dy_1,dz_1,dx_tilde,dy_tilde,dz_tilde)
!
!  Read grid in single precision
!
!  23-oct-13/MR: derived from input_grid
!  28-oct-13/MR: added lcont and location parameters to calls of outlog where appropriate
!
      real(KIND=rkind4),                intent(OUT) :: dx,dy,dz,Lx,Ly,Lz
      real(KIND=rkind4), dimension (mx),intent(OUT) :: x,dx_1,dx_tilde
      real(KIND=rkind4), dimension (my),intent(OUT) :: y,dy_1,dy_tilde
      real(KIND=rkind4), dimension (mz),intent(OUT) :: z,dz_1,dz_tilde

      integer :: io_err
      logical :: lerror
      real(KIND=rkind4) :: t_sp   ! t in single precision for backwards compatibility
!
      read(lun_input,IOSTAT=io_err) t_sp,x,y,z,dx,dy,dz
      lerror = outlog(io_err,"main data block",location='input_grid_single', lcont=.true.)
      read(lun_input,IOSTAT=io_err) dx,dy,dz
      lerror = outlog(io_err,"dx,dy,dz",lcont=.true.)
      read(lun_input,IOSTAT=io_err) Lx,Ly,Lz
      if (io_err < 0) then
        ! End-Of-File: give notification that box dimensions are not read.
        ! This should only happen when reading old files.
        ! We should allow this for the time being.
        call warning ('input_grid', "Lx,Ly,Lz are not yet in grid.dat")
      else
        lerror = outlog(io_err,"Lx,Ly,Lz")
        read(lun_input,IOSTAT=io_err) dx_1,dy_1,dz_1
        lerror = outlog(io_err,"dx_1,dy_1,dz_1")
        read(lun_input,IOSTAT=io_err) dx_tilde,dy_tilde,dz_tilde
        lerror = outlog(io_err,"dx_tilde,dy_tilde,dz_tilde")
      endif
!
    endsubroutine input_grid_single
!***********************************************************************
    subroutine input_grid_double(x,y,z,dx,dy,dz,Lx,Ly,Lz,dx_1,dy_1,dz_1,dx_tilde,dy_tilde,dz_tilde)
!
!  Read grid in double precision
!
!  23-oct-13/MR: derived from input_grid
!  28-oct-13/MR: added lcont and location parameters to calls of outlog where appropriate
!
      real(KIND=rkind8),                intent(OUT) :: dx,dy,dz,Lx,Ly,Lz
      real(KIND=rkind8), dimension (mx),intent(OUT) :: x,dx_1,dx_tilde
      real(KIND=rkind8), dimension (my),intent(OUT) :: y,dy_1,dy_tilde
      real(KIND=rkind8), dimension (mz),intent(OUT) :: z,dz_1,dz_tilde

      integer :: io_err
      logical :: lerror
      real(KIND=rkind8) :: t_sp   ! t in single precision for backwards compatibility
!
      read(lun_input,IOSTAT=io_err) t_sp,x,y,z,dx,dy,dz
      lerror = outlog(io_err,"main data block",location='input_grid_double',lcont=.true.)
      read(lun_input,IOSTAT=io_err) dx,dy,dz
      lerror = outlog(io_err,"dx,dy,dz",lcont=.true.)
      read(lun_input,IOSTAT=io_err) Lx,Ly,Lz
      if (io_err < 0) then
        ! End-Of-File: give notification that box dimensions are not read.
        ! This should only happen when reading old files.
        ! We should allow this for the time being.
        call warning ('input_grid_double', "Lx,Ly,Lz are not yet in grid.dat")
      else
        lerror = outlog(io_err,"Lx,Ly,Lz",lcont=.true.)
        read(lun_input,IOSTAT=io_err) dx_1,dy_1,dz_1
        lerror = outlog(io_err,"dx_1,dy_1,dz_1",lcont=.true.)
        read(lun_input,IOSTAT=io_err) dx_tilde,dy_tilde,dz_tilde
        lerror = outlog(io_err,"dx_tilde,dy_tilde,dz_tilde",lcont=.true.)
      endif
!
    endsubroutine input_grid_double
!***********************************************************************
    subroutine rgrid (file)
!
!  Read processor-local part of grid coordinates.
!
!  21-jan-02/wolf: coded
!  15-jun-03/axel: Lx,Ly,Lz are now read in from file (Tony noticed the mistake)
!  24-oct-13/MR  : handling of reading from different precision introduced
!  28-oct-13/MR  : added overwriting of grid.dat if restart from different precision
!   3-mar-15/MR  : calculation of d[xyz]2_bound added: contain twice the distances of
!                  three neighbouring points from the boundary point
!  15-apr-15/MR  : automatic detection of precision added
!
      use File_io, only: file_size
!
      character (len=*) :: file
!
      integer :: io_err, datasize, filesize
      integer, parameter :: nrec=5
      logical :: lerror, lotherprec
!
      real(KIND=rkind8), dimension(:), allocatable :: xdb,ydb,zdb,dx_1db,dy_1db,dz_1db,dx_tildedb,dy_tildedb,dz_tildedb
      real(KIND=rkind4), dimension(:), allocatable :: xsg,ysg,zsg,dx_1sg,dy_1sg,dz_1sg,dx_tildesg,dy_tildesg,dz_tildesg

      real(KIND=rkind8) :: dxdb,dydb,dzdb,Lxdb,Lydb,Lzdb
      real(KIND=rkind4) :: dxsg,dysg,dzsg,Lxsg,Lysg,Lzsg

      open(lun_input,FILE=trim(directory)//'/'//file,FORM='unformatted',IOSTAT=io_err,status='old')
      if (io_err /= 0) call fatal_error('rgrid', &
          "Cannot open " // trim(file) // " (or similar) for reading" // &
          " -- is data/ visible from all nodes?",.true.)
      lerror = outlog(io_err,'openr',file,location='rgrid')

      if (lread_from_other_prec) then

        datasize = 3*(mx+my+mz) + 10
        filesize = file_size(trim(directory)//'/'//file) - 8*nrec
!
        if (kind(x)==rkind4) then
          lotherprec = filesize/=4*datasize
          if (lotherprec) then
            allocate(xdb(mx),ydb(my),zdb(mz),dx_1db(mx),dy_1db(my),dz_1db(mz),dx_tildedb(mx),dy_tildedb(my),dz_tildedb(mz))
            call input_grid(xdb,ydb,zdb,dxdb,dydb,dzdb,Lxdb,Lydb,Lzdb, &
                            dx_1db,dy_1db,dz_1db,dx_tildedb,dy_tildedb,dz_tildedb)
            x=xdb; y=ydb; z=zdb; dx=dxdb; dy=dydb; dz=dzdb
            Lx=Lxdb; Ly=Lydb; Lz=Lzdb; dx_1=dx_1db; dy_1=dy_1db; dz_1=dz_1db
            dx_tilde=dx_tildedb; dy_tilde=dy_tildedb; dz_tilde=dz_tildedb
          endif
        elseif (kind(x)==rkind8) then
          lotherprec = filesize/=8*datasize
          if (lotherprec) then
            allocate(xsg(mx),ysg(my),zsg(mz),dx_1sg(mx),dy_1sg(my),dz_1sg(mz),dx_tildesg(mx),dy_tildesg(my),dz_tildesg(mz))
            call input_grid(xsg,ysg,zsg,dxsg,dysg,dzsg,Lxsg,Lysg,Lzsg, &
                            dx_1sg,dy_1sg,dz_1sg,dx_tildesg,dy_tildesg,dz_tildesg)
            x=xsg; y=ysg; z=zsg; dx=dxsg; dy=dysg; dz=dzsg
            Lx=Lxsg; Ly=Lysg; Lz=Lzsg; dx_1=dx_1sg; dy_1=dy_1sg; dz_1=dz_1sg;
            dx_tilde=dx_tildesg; dy_tilde=dy_tildesg; dz_tilde=dz_tildesg
          endif
        endif
      else
        call input_grid(x,y,z,dx,dy,dz,Lx,Ly,Lz,dx_1,dy_1,dz_1,dx_tilde,dy_tilde,dz_tilde)
      endif
      close(lun_input,IOSTAT=io_err)
      lerror = outlog(io_err,'close')
!
      if (lread_from_other_prec.and.lotherprec) call wgrid(file)         ! perhaps not necessary
!
!  Find minimum/maximum grid spacing. Note that
!    minval( (/dx,dy,dz/), MASK=((/nxgrid,nygrid,nzgrid/) > 1) )
!  will be undefined if all n[x-z]grid=1, so we have to add the fourth
!  component with a test that is always true
!
      dxmin = minval( (/dx,dy,dz,huge(dx)/), &
                MASK=((/nxgrid,nygrid,nzgrid,2/) > 1) )
      dxmax = maxval( (/dx,dy,dz,epsilon(dx)/), &
                MASK=((/nxgrid,nygrid,nzgrid,2/) > 1) )
!
!  Fill pencil with maximum gridspacing. Will be overwritten
!  during the mn loop in the non equidistant case
!
      dxmax_pencil = dxmax
      dxmin_pencil = dxmin
!
!  debug output
!
      if (ip<=4.and.lroot) then
        print*,'rgrid: Lx,Ly,Lz=',Lx,Ly,Lz
        print*,'rgrid: dx,dy,dz=',dx,dy,dz
        print*,'rgrid: dxmin,dxmax=',dxmin,dxmax
      endif
!
!  should stop if dxmin=0
!
      if (dxmin==0) call fatal_error("rgrid", "check Lx,Ly,Lz: is one of them 0?")
!
    endsubroutine rgrid
!***********************************************************************
    subroutine wproc_bounds(file)
!
!   Export processor boundaries to file.
!
!   10-jul-08/kapelrud: coded
!   16-Feb-2012/Bourdin.KIS: rewritten
!
      character (len=*) :: file
!
      integer :: io_err
      logical :: lerror
!
      call delete_file(file) 
      open(lun_output,FILE=file,FORM='unformatted',IOSTAT=io_err,status='new')
      lerror = outlog(io_err,"openw",file,location='wproc_bounds')
      write(lun_output,IOSTAT=io_err) procx_bounds
      lerror = outlog(io_err,'procx_bounds')
      write(lun_output,IOSTAT=io_err) procy_bounds
      lerror = outlog(io_err,'procy_bounds')
      write(lun_output,IOSTAT=io_err) procz_bounds
      lerror = outlog(io_err,'procz_bounds')
      close(lun_output,IOSTAT=io_err)
      lerror = outlog(io_err,'close')
!
    endsubroutine wproc_bounds
!***********************************************************************
    subroutine rproc_bounds(file)
!
!   Import processor boundaries from file.
!
!   10-jul-08/kapelrud: coded
!   16-Feb-2012/Bourdin.KIS: rewritten
!
      character (len=*) :: file
!
      integer :: io_err
      logical :: lerror
      real(KIND=rkind4), dimension(0:nprocx):: procx_boundssg
      real(KIND=rkind4), dimension(0:nprocy):: procy_boundssg
      real(KIND=rkind4), dimension(0:nprocz):: procz_boundssg
!
      real(KIND=rkind8), dimension(0:nprocx):: procx_boundsdb
      real(KIND=rkind8), dimension(0:nprocy):: procy_boundsdb
      real(KIND=rkind8), dimension(0:nprocz):: procz_boundsdb
!
      open(lun_input,FILE=file,FORM='unformatted',IOSTAT=io_err,status='old')

      if (lread_from_other_prec) then
        if (kind(x)==rkind4) then
          call input_proc_bounds(procx_boundsdb,procy_boundsdb,procz_boundsdb)
          procx_bounds=procx_boundsdb; procy_bounds=procy_boundsdb; procz_bounds=procz_boundsdb
        elseif (kind(x)==rkind8) then
          call input_proc_bounds(procx_boundssg,procy_boundssg,procz_boundssg)
          procx_bounds=procx_boundssg; procy_bounds=procy_boundssg; procz_bounds=procz_boundssg
        endif
      else
        call input_proc_bounds(procx_bounds,procy_bounds,procz_bounds)
      endif

      close(lun_output,IOSTAT=io_err)
      lerror = outlog(io_err,'close')
!
    endsubroutine rproc_bounds
!***********************************************************************
    subroutine input_proc_bounds_double(procx_bounds,procy_bounds,procz_bounds)
!
!   Import processor boundaries from file.in double precision
!
!   23-oct-13/MR: derivced from rproc_bounds
!
      real(KIND=rkind8), dimension(0:nprocx), intent(OUT):: procx_bounds
      real(KIND=rkind8), dimension(0:nprocy), intent(OUT):: procy_bounds
      real(KIND=rkind8), dimension(0:nprocz), intent(OUT):: procz_bounds

      integer :: io_err
      logical :: lerror
!
      read(lun_input,IOSTAT=io_err) procx_bounds
      lerror = outlog(io_err,'procx_bounds')
      read(lun_input,IOSTAT=io_err) procy_bounds
      lerror = outlog(io_err,'procy_bounds')
      read(lun_input,IOSTAT=io_err) procz_bounds
      lerror = outlog(io_err,'procz_bounds')
!
    endsubroutine input_proc_bounds_double
!***********************************************************************
    subroutine input_proc_bounds_single(procx_bounds,procy_bounds,procz_bounds)
!
!   Import processor boundaries from file.in single precision
!
!   23-oct-13/MR: derivced from rproc_bounds
!
      real(KIND=rkind4), dimension(0:nprocx), intent(OUT):: procx_bounds
      real(KIND=rkind4), dimension(0:nprocy), intent(OUT):: procy_bounds
      real(KIND=rkind4), dimension(0:nprocz), intent(OUT):: procz_bounds

      integer :: io_err
      logical :: lerror
!
      read(lun_input,IOSTAT=io_err) procx_bounds
      lerror = outlog(io_err,'procx_bounds')
      read(lun_input,IOSTAT=io_err) procy_bounds
      lerror = outlog(io_err,'procy_bounds')
      read(lun_input,IOSTAT=io_err) procz_bounds
      lerror = outlog(io_err,'procz_bounds')
!
    endsubroutine input_proc_bounds_single
!***********************************************************************
endmodule Io
