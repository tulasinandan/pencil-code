! $Id$
!
!  This module contains useful subroutines for the particle modules.
!  Subroutines that depend on domain decomposition should be put in
!  the Particles_map module.
!
module Particles_sub
!
  use Cdata
  use General, only: keep_compiler_quiet
  use Messages
  use Particles_cdata
  use Particles_mpicomm
!
  implicit none
!
  private
!
  public :: input_particles, output_particles, boundconds_particles
  public :: sum_par_name, max_par_name, sum_par_name_nw, integrate_par_name
  public :: remove_particle, get_particles_interdistance
  public :: count_particles, output_particle_size_dist
  public :: get_rhopswarm, find_grid_volume, find_interpolation_weight
  public :: find_interpolation_indeces, get_gas_density, precalc_cell_volumes
!
  interface get_rhopswarm
    module procedure get_rhopswarm_ineargrid
    module procedure get_rhopswarm_point
    module procedure get_rhopswarm_pencil
    module procedure get_rhopswarm_block
  endinterface
!
  contains
!***********************************************************************
    subroutine input_particles(filename,fp,ipar)
!
!  Read snapshot file with particle data.
!
!  29-dec-04/anders: adapted from input
!
      use Mpicomm, only: mpireduce_max_scl_int
!
      real, dimension (mpar_loc,mparray) :: fp
      character (len=*) :: filename
      integer, dimension (mpar_loc) :: ipar
!
      intent (in) :: filename
      intent (out) :: fp,ipar
!
      open(1,FILE=filename,FORM='unformatted')
!
!  First read the number of particles present at the processor and the index
!  numbers of the particles.
!
        read(1) npar_loc
        if (npar_loc/=0) read(1) ipar(1:npar_loc)
!
!  Then read particle data.
!
        if (npar_loc/=0) read(1) fp(1:npar_loc,:)
!
!  Read snapshot time.
!
!        read(1) t
!
        if (ip<=8) print*, 'input_particles: read ', filename
!
      close(1)
!
!  If we are inserting particles contiuously during the run root must
!  know the total number of particles in the simulation.
!
      if (npar_loc/=0) then
        call mpireduce_max_scl_int(maxval(ipar(1:npar_loc)),npar_total)
      else
        call mpireduce_max_scl_int(npar_loc,npar_total)
      endif
!
    endsubroutine input_particles
!***********************************************************************
    subroutine output_particles(filename,fp,ipar)
!
!  Write snapshot file with particle data.
!
!  29-dec-04/anders: adapted from output
!
      character(len=*) :: filename
      real, dimension (mpar_loc,mparray) :: fp
      integer, dimension(mpar_loc) :: ipar
      real :: t_sp   ! t in single precision for backwards compatibility
!
      intent (in) :: filename, ipar
!
      t_sp = t
      if (ip<=8.and.lroot) print*,'output_particles: writing snapshot file '// &
          filename
!
      open(lun_output,FILE=filename,FORM='unformatted')
!
!  First write the number of particles present at the processor and the index
!  numbers of the particles.
!
        write(lun_output) npar_loc
        if (npar_loc/=0) write(lun_output) ipar(1:npar_loc)
!
!  Then write particle data.
!
        if (npar_loc/=0) write(lun_output) fp(1:npar_loc,:)
!
!  Write time and grid parameters.
!
        write(lun_output) t_sp, x, y, z, dx, dy, dz
!
      close(lun_output)
!
    endsubroutine output_particles
!***********************************************************************
    subroutine boundconds_particles(fp,ipar,dfp,linsert)
!
!  Global boundary conditions for particles.
!
!  30-dec-04/anders: coded
!
      use Mpicomm
      use General, only: random_number_wrapper
      use Particles_mpicomm
!
      real, dimension (mpar_loc,mparray) :: fp
      integer, dimension (mpar_loc) :: ipar
      real, dimension (mpar_loc,mpvar), optional :: dfp
      logical, optional :: linsert
!
      real :: xold, yold, rad, r1old, OO
      integer :: k, ik, k1, k2
      character (len=2*bclen+1) :: boundx, boundy, boundz
      logical :: lnbody
!
      intent (inout) :: fp, ipar, dfp
!
!  Reversing direction of looping is needed for removal.
!
      if ((bcpx=='rmv').or.(bcpy=='rmv').or.(bcpz=='rmv')) then
        k1=npar_loc; k2=1; ik=-1
      else
        k1=1; k2=npar_loc; ik=1
      endif
!
      do k=k1,k2,ik
!
!  Check if we are dealing with a dust or a massive particle
!
        lnbody=(lparticles_nbody.and.any(ipar(k)==ipar_nbody))
        if (.not.lnbody) then
          boundx=bcpx ; boundy=bcpy ; boundz=bcpz
        else
          boundx=bcspx; boundy=bcspy; boundz=bcspz
        endif
!
!  Calculate rad for cylinder-in-a-box calculations
!
        if (lcylinder_in_a_box) then
          rad = sqrt(fp(k,ixp)**2 + fp(k,iyp)**2)
        endif
!
!  Cartesian boundaries: Boundary condition in the x-direction. The physical
!  domain is in the interval
!
!    x \in [x0,x1[
!    y \in [y0,y1[
!    z \in [z0,z1[
!
        if (nxgrid/=1) then
          if (boundx=='p') then
!  xp < x0
            if (fp(k,ixp)< xyz0(1)) then
              fp(k,ixp)=fp(k,ixp)+Lxyz(1)
              if (lshear.and.nygrid/=1) then
                fp(k,iyp)=fp(k,iyp)-deltay
!
!  Keep track of energy gain or lose from shearing boundaries.
!
                if (energy_gain_shear_bcs/=impossible) &
                    energy_gain_shear_bcs=energy_gain_shear_bcs + &
                    (1.0/6.0)*Sshear**2*Omega**2*Lx**2 + &
                    Sshear*(fp(k,ivpy)+Sshear*fp(k,ixp))*Lx - &
                    (4.0/3.0)*Sshear**2*fp(k,ixp)*Lx
              endif
!  Particle position must never need more than one addition of Lx to get back
!  in the box. Often a NaN or Inf in the particle position will show up as a
!  problem here.
              if (fp(k,ixp)< xyz0(1)) then
                print*, 'boundconds_particles: ERROR - particle ', ipar(k), &
                     ' was further than Lx outside the simulation box!'
                print*, 'This must never happen.'
                print*, 'iproc, ipar, xxp=', iproc, ipar(k), fp(k,ixp:izp)
                call fatal_error_local('boundconds_particles','')
              endif
              if (ipyy/=0) fp(k,ipxx)=fp(k,ipxx)+Lxyz(1)
            endif
!  xp > x1
            if (fp(k,ixp)>=xyz1(1)) then
              fp(k,ixp)=fp(k,ixp)-Lxyz(1)
              if (lshear.and.nygrid/=1) then
                fp(k,iyp)=fp(k,iyp)+deltay
!
!  Keep track of energy gain or lose from shearing boundaries.
!
                if (energy_gain_shear_bcs/=impossible) &
                    energy_gain_shear_bcs=energy_gain_shear_bcs + &
                    (1.0/6.0)*Sshear**2*Omega**2*Lx**2 - &
                    Sshear*(fp(k,ivpy)+Sshear*fp(k,ixp))*Lx + &
                    (4.0/3.0)*Sshear**2*fp(k,ixp)*Lx
              endif
              if (fp(k,ixp)>=xyz1(1)) then
                print*, 'boundconds_particles: ERROR - particle ', ipar(k), &
                     ' was further than Lx outside the simulation box!'
                print*, 'This must never happen.'
                print*, 'iproc, ipar, xxp=', iproc, ipar(k), fp(k,ixp:izp)
                call fatal_error_local('boundconds_particles','')
              endif
              if (ipxx/=0) fp(k,ipxx)=fp(k,ipxx)-Lxyz(1)
            endif
          elseif (boundx=='out') then
!
!  Do nothing. A massive particle, can be out of the box. A star, for example,
!  in a cylindrical simulation
!
          elseif (boundx=='flk') then
!
!  Flush-Keplerian - flush the particle to the outer boundary with keplerian
!  speed
!
            if (lcylindrical_coords) then
              if ((fp(k,ixp)< rp_int).or.(fp(k,ixp)>= rp_ext)) then
!   Flush to outer boundary
                fp(k,ixp)  = rp_ext
!   Random new azimuthal y position
                call random_number_wrapper(fp(k,iyp))
                fp(k,iyp)=xyz0_loc(2)+fp(k,iyp)*Lxyz_loc(2)
!   Zero radial, Keplerian azimuthal, velocities
                fp(k,ivpx) = 0.
!   Keplerian azimuthal velocity
                fp(k,ivpy) = fp(k,ixp)**(-1.5)
              endif
!
            elseif (lcartesian_coords) then
!
! The Cartesian case has the option cylinder_in_a_box, sphere_in_a_box
! and nothing (assumed to be the common shearing box. Only the cylinder
! is considered. The code will break otherwise
!
              if (lcylinder_in_a_box) then
!
                if (boundy/='out') then
                  call fatal_error_local("boundconds_particles",&
                       "The radial boundary already does it all"//&
                       "so the y-boundary has to be set to 'out'")
                endif
!
                if ((rad<=rp_int).or.(rad>rp_ext)) then
!  Flush to outer boundary
                  xold=fp(k,ixp); yold=fp(k,iyp); r1old = 1./max(rad,tini)
                  fp(k,ixp) = rp_ext*xold*r1old ! r*cos(theta)
                  fp(k,iyp) = rp_ext*yold*r1old ! r*sin(theta)
!  Set particle velocity to local Keplerian speed.
                  OO=rp_ext**(-1.5)
                  fp(k,ivpx) = -OO*fp(k,iyp)
                  fp(k,ivpy) =  OO*fp(k,ixp)
                endif
              else
                call fatal_error_local('boundconds_particles',&
                     'no clue how to do flush-keplerian in a cartesian box')
              endif
            elseif (lspherical_coords) then
              call fatal_error_local('boundconds_particles',&
                   'flush-keplerian not ready for spherical coords')
            endif
!
          elseif (boundx=='rmv') then
!
!  Remove the particle from the simulation
!
            if (lspherical_coords.or.lcylindrical_coords) then
              if ((fp(k,ixp)< rp_int).or.(fp(k,ixp)>= rp_ext)) then
                if (present(dfp)) then
                  call remove_particle(fp,ipar,k,dfp)
                else
                  call remove_particle(fp,ipar,k)
                endif
              endif
            elseif (lcartesian_coords) then
              if (lcylinder_in_a_box) then
                if ((rad< rp_int).or.(rad>= rp_ext)) then
                  if (present(dfp)) then
                    call remove_particle(fp,ipar,k,dfp)
                  else
                    call remove_particle(fp,ipar,k)
                  endif
                endif
              else
                if (fp(k,ixp)<=xyz0(1) .or. fp(k,ixp)>=xyz1(1)) then
                  if (present(dfp)) then
                    call remove_particle(fp,ipar,k,dfp)
                  else
                    call remove_particle(fp,ipar,k)
                  endif
                endif
              endif
            endif
          elseif (boundx=='hw') then
!
!  Hard wall boundary condition
!
            if (fp(k,ixp)<=xyz0(1)) then
              fp(k,ixp)=2*xyz0(1)-fp(k,ixp)
              fp(k,ivpx)=-fp(k,ivpx)
            elseif (fp(k,ixp)>=xyz1(1)) then
              fp(k,ixp)=2*xyz1(1)-fp(k,ixp)
              fp(k,ivpx)=-fp(k,ivpx)
            endif
          else
            print*, 'boundconds_particles: No such boundary condition =', boundx
            call stop_it('boundconds_particles')
          endif
        endif
!
!  Boundary condition in the y-direction.
!
        if (nygrid/=1) then
          if (boundy=='p') then
!  yp < y0
            if (fp(k,iyp)< xyz0(2)) then
              fp(k,iyp)=fp(k,iyp)+Lxyz(2)
              if (fp(k,iyp)< xyz0(2)) then
                print*, 'boundconds_particles: ERROR - particle ', ipar(k), &
                     ' was further than Ly outside the simulation box!'
                print*, 'This must never happen.'
                print*, 'iproc, ipar, xxp=', iproc, ipar(k), fp(k,ixp:izp)
                call fatal_error_local('boundconds_particles','')
              endif
              if (ipyy/=0) fp(k,ipyy)=fp(k,ipyy)+Lxyz(2)
            endif
!  yp > y1
            if (fp(k,iyp)>=xyz1(2)) then
              fp(k,iyp)=fp(k,iyp)-Lxyz(2)
              if (fp(k,iyp)>=xyz1(2)) then
                print*, 'boundconds_particles: ERROR - particle ', ipar(k), &
                     ' was further than Ly outside the simulation box!'
                print*, 'This must never happen.'
                print*, 'iproc, ipar, xxp=', iproc, ipar(k), fp(k,ixp:izp)
                call fatal_error_local('boundconds_particles','')
              endif
              if (ipyy/=0) fp(k,ipyy)=fp(k,ipyy)-Lxyz(2)
            endif
          elseif (boundy=='out') then
            ! massive particles can be out of the box
            ! the star, for example, in a cylindrical simulation
          elseif (boundy=='rmv') then
            if (lcartesian_coords) then
              if (fp(k,iyp)<=xyz0(2) .or. fp(k,iyp)>=xyz1(2)) then
                if (present(dfp)) then
                  call remove_particle(fp,ipar,k,dfp)
                else
                  call remove_particle(fp,ipar,k)
                endif
              endif
            endif
          elseif (boundy=='hw') then
!
!  Hard wall boundary condition
!
            if (fp(k,iyp)<=xyz0(2)) then
              fp(k,iyp)=2*xyz0(2)-fp(k,iyp)
              fp(k,ivpy)=-fp(k,ivpy)
            elseif (fp(k,iyp)>=xyz1(2)) then
              fp(k,iyp)=2*xyz1(2)-fp(k,iyp)
              fp(k,ivpy)=-fp(k,ivpy)
            endif
          else
            print*, 'boundconds_particles: No such boundary condition =', boundy
            call stop_it('boundconds_particles')
          endif
        endif
!
!  Boundary condition in the z-direction.
!
        if (nzgrid/=1) then
          if (boundz=='p') then
!  zp < z0
            if (fp(k,izp)< xyz0(3)) then
              fp(k,izp)=fp(k,izp)+Lxyz(3)
              if (fp(k,izp)< xyz0(3)) then
                print*, 'boundconds_particles: ERROR - particle ', ipar(k), &
                     ' was further than Lz outside the simulation box!'
                print*, 'This must never happen.'
                print*, 'iproc, ipar, xxp=', iproc, ipar(k), fp(k,ixp:izp)
                call fatal_error_local('boundconds_particles','')
              endif
              if (ipzz/=0) fp(k,ipzz)=fp(k,ipzz)+Lxyz(3)
            endif
!  zp > z1
            if (fp(k,izp)>=xyz1(3)) then
              fp(k,izp)=fp(k,izp)-Lxyz(3)
              if (fp(k,izp)>=xyz1(3)) then
                print*, 'boundconds_particles: ERROR - particle ', ipar(k), &
                     ' was further than Lz outside the simulation box!'
                print*, 'This must never happen.'
                print*, 'iproc, ipar, xxp=', iproc, ipar(k), fp(k,ixp:izp)
                call fatal_error_local('boundconds_particles','')
              endif
              if (ipzz/=0) fp(k,ipzz)=fp(k,ipzz)-Lxyz(3)
            endif
          elseif (boundz=='out') then
            ! massive particles can be out of the box
            ! the star, for example, in a cylindrical simulation
          elseif (boundz=='rmv') then
            if (lcartesian_coords) then
              if (fp(k,izp)<=xyz0(3) .or. fp(k,izp)>=xyz1(3)) then
                if (present(dfp)) then
                  call remove_particle(fp,ipar,k,dfp)
                else
                  call remove_particle(fp,ipar,k)
                endif
              endif
            endif
          elseif (boundz=='ref') then
            if ((fp(k,izp)< xyz0(3)) .or. (fp(k,izp)>=xyz1(3))) then
              fp(k,ivpz)=-fp(k,ivpz)
              if (fp(k,izp)< xyz0(3)) then
                fp(k,izp)=2*xyz0(3)-fp(k,izp)
              endif
              if (fp(k,izp)>=xyz1(3)) then
                fp(k,izp)=2*xyz1(3)-fp(k,izp)
              endif
            endif
          elseif (boundz=='hw') then
!
!  Hard wall boundary condition
!
            if (fp(k,izp)<=xyz0(3)) then
              fp(k,izp)=2*xyz0(3)-fp(k,izp)
              fp(k,ivpz)=-fp(k,ivpz)
            elseif (fp(k,izp)>=xyz1(3)) then
              fp(k,izp)=2*xyz1(3)-fp(k,izp)
              fp(k,ivpz)=-fp(k,ivpz)
            endif
          elseif (boundz=='inc') then
!
!  Move particle from the boundary to the center of the box
!
            if (fp(k,izp)<=xyz0(3) .or. fp(k,izp)>=xyz1(3)) then
              fp(k,izp)=xyz0(3)+(xyz1(3)-xyz0(3))/2.
              fp(k,ivpx:ivpz)=0.
            endif
          else
            print*, 'boundconds_particles: No such boundary condition=', boundz
            call stop_it('boundconds_particles')
          endif
        endif
      enddo
!
!  Redistribute particles among processors (internal boundary conditions).
!
      if (lmpicomm) then
        if (present(dfp)) then
          if (present(linsert)) then
            call migrate_particles(fp,ipar,dfp,linsert=.true.)
          else
            call migrate_particles(fp,ipar,dfp)
          endif
        else
          if (present(linsert)) then
            call migrate_particles(fp,ipar,linsert=.true.)
          else
            call migrate_particles(fp,ipar)
          endif
        endif
      endif
!
    endsubroutine boundconds_particles
!***********************************************************************
    subroutine sum_par_name(a,iname,lsqrt)
!
!  Successively calculate sum of a, which is supplied at each call.
!  Works for particle diagnostics. The number of particles is stored as
!  a weight used later for normalisation of sum.
!
!  TODO: All processors must enter this subroutine in order to set the
!        diagnostics type right, even processors with no particles.
!        One can do this by calling sum_par_name(fp(1:npar_loc,ixp),...),
!        which sends an array of zero size. This is a bug and needs to be
!        fixed.
!
!  02-jan-05/anders: adapted from sum_mn_name
!
      real, dimension (:) :: a
      integer :: iname
      logical, optional :: lsqrt
!
      integer, dimension(mname), save :: icount=0
!
      if (iname/=0) then
!
        if (icount(iname)==0) then
          fname(iname)=0.0
          fweight(iname)=0.0
        endif
!
        fname(iname)  =fname(iname)  +sum(a)
        fweight(iname)=fweight(iname)+size(a)
!
!  Set corresponding entry in itype_name
!
        if (present(lsqrt)) then
          itype_name(iname)=ilabel_sum_sqrt_par
        else
          itype_name(iname)=ilabel_sum_par
        endif
!
!  Reset sum when npar_loc particles have been considered.
!
        icount(iname)=icount(iname)+size(a)
        if (icount(iname)==npar_loc) then
          icount(iname)=0
        elseif (icount(iname)>=npar_loc) then
          print*, 'sum_par_name: Too many particles entered this sub.'
          print*, 'sum_par_name: Can only do statistics on npar_loc particles!'
          call fatal_error('sum_par_name','')
        endif
!
      endif
!
    endsubroutine sum_par_name
!***********************************************************************
    subroutine sum_par_name_nw(a,iname,lsqrt)
!
!  successively calculate sum of a, which is supplied at each call.
!  Works for particle diagnostics.
!
!  22-aug-05/anders: adapted from sum_par_name
!
      real, dimension (:) :: a
      integer :: iname
      logical, optional :: lsqrt
!
      integer, save :: icount=0
!
      if (iname/=0) then
!
        if (icount==0) fname(iname)=0
!
        fname(iname)=fname(iname)+sum(a)
!
!  Set corresponding entry in itype_name
!
        if (present(lsqrt)) then
          itype_name(iname)=ilabel_sum_sqrt
        else
          itype_name(iname)=ilabel_sum
        endif
!
        icount=icount+size(a)
        if (icount==nw) then
          icount=0
        elseif (icount>=nw) then
          print*, 'sum_par_name_nw: Too many grid points entered this sub.'
          print*, 'sum_par_name_nw: Can only do statistics on nw grid points!'
          call fatal_error('sum_par_name_nw','')
        endif
!
      endif
!
    endsubroutine sum_par_name_nw
!***********************************************************************
    subroutine max_par_name(a,iname,lneg)
!
!  Successively calculate maximum of a, which is supplied at each call.
!  Works for particle diagnostics.
!
!  28-nov-05/anders: adapted from max_par_name
!
      real, dimension (:) :: a
      integer :: iname
      logical, optional :: lneg
!
      if (iname/=0) then
!
        fname(iname)=0.
        fname(iname)=fname(iname)+maxval(a)
!
!  Set corresponding entry in itype_name.
!
        if (present(lneg)) then
          itype_name(iname)=ilabel_max_neg
        else
          itype_name(iname)=ilabel_max
        endif
!
      endif
!
    endsubroutine max_par_name
!***********************************************************************
    subroutine integrate_par_name(a,iname)
!
!  Calculate integral of a, which is supplied at each call.
!  Works for particle diagnostics.
!
!  29-nov-05/anders: adapted from sum_par_name
!
      real, dimension (:) :: a
      integer :: iname
!
      integer, save :: icount=0
!
      if (iname/=0) then
!
        if (icount==0) fname(iname)=0
!
        fname(iname)=fname(iname)+sum(a)
!
!  Set corresponding entry in itype_name.
!
        itype_name(iname)=ilabel_integrate
!
!  Reset sum when npar_loc particles have been considered.
!
        icount=icount+size(a)
        if (icount==npar_loc) then
          icount=0
        elseif (icount>=npar_loc) then
          print*, 'integral_par_name: Too many particles entered this sub.'
          print*, 'integral_par_name: Can only do statistics on npar_loc particles!'
          call fatal_error('integral_par_name','')
        endif
!
      endif
!
    endsubroutine integrate_par_name
!***********************************************************************
    subroutine sharpen_tsc_density(f)
!
!  Sharpen density amplitudes (experimental).
!
!   9-nov-06/anders: coded
!
      use Fourier
!
      real, dimension (mx,my,mz,mfarray) :: f
!
      real, dimension (:,:,:), allocatable :: a1, b1
      integer :: ikx, iky, ikz, stat
      real :: k2, k4
!
!  Allocate memory for large arrays.
!
      allocate(a1(nx,ny,nz),stat=stat)
      if (stat>0) call fatal_error('sharpen_tsc_density', &
          'Could not allocate memory for a1')
      allocate(b1(nx,ny,nz),stat=stat)
      if (stat>0) call fatal_error('sharpen_tsc_density', &
          'Could not allocate memory for b1')
!
      a1=f(l1:l2,m1:m2,n1:n2,irhop)
      b1=0.0
      if (lshear) then
        call fourier_transform_shear(a1,b1)
      else
        call fourier_transform(a1,b1)
      endif
      do ikz=1,nz; do iky=1,ny; do ikx=1,nx
        k2 = kx_fft(ikx)**2 + ky_fft(iky+ipy*ny)**2 + kz_fft(ikz+ipz*nz)**2
        k4 = kx_fft(ikx)**4 + ky_fft(iky+ipy*ny)**4 + kz_fft(ikz+ipz*nz)**4
        a1(ikx,iky,ikz)=a1(ikx,iky,ikz)/(1-dx**2*k2/8+13*dx**4*k4/1920)
        b1(ikx,iky,ikz)=b1(ikx,iky,ikz)/(1-dx**2*k2/8+13*dx**4*k4/1920)
      enddo; enddo; enddo
      if (lshear) then
        call fourier_transform_shear(a1,b1,linv=.true.)
      else
        call fourier_transform(a1,b1,linv=.true.)
      endif
      f(l1:l2,m1:m2,n1:n2,irhop)=a1
!
!  Deallocate arrays.
!
      if (allocated(a1)) deallocate(a1)
      if (allocated(b1)) deallocate(b1)
!
    endsubroutine sharpen_tsc_density
!***********************************************************************
    subroutine get_particles_interdistance(xx1,xx2,vector,distance,lsquare)
!
!  The name of the subroutine is pretty self-explanatory.
!
!  14-mar-08/wlad: moved here from particles_nbody
!
      real,dimension(3) :: xx1,xx2,evr
      real :: e1,e2,e3,e10,e20,e30
      real,dimension(3),optional :: vector
      real,optional :: distance
      logical,optional :: lsquare
!
      e1=xx1(1);e10=xx2(1)
      e2=xx1(2);e20=xx2(2)
      e3=xx1(3);e30=xx2(3)
!
!  Get the distances in each ortogonal component.
!  These are NOT (x,y,z) for all.
!  For cartesian it is (x,y,z), for cylindrical (s,phi,z)
!  for spherical (r,theta,phi)
!
      if (lcartesian_coords) then
        evr(1) = e1 - e10
        evr(2) = e2 - e20
        evr(3) = e3 - e30
      elseif (lcylindrical_coords) then
        evr(1) = e1 - e10*cos(e2-e20)
        evr(2) = e10*sin(e2-e20)
        evr(3) = e3 - e30
      elseif (lspherical_coords) then
        evr(1) = e1 - e10*sin(e2)*sin(e20)*cos(e3-e30)
        evr(2) = e10*(sin(e2)*cos(e20) - cos(e2)*sin(e20)*cos(e3-e30))
        evr(3) = e10*sin(e20)*sin(e3-e30)
      endif
!
!  Particles relative distance from each other
!
!  r_ij = sqrt(ev1**2 + ev2**2 + ev3**2)
!  invr3_ij = r_ij**(-3)
!
      if (present(distance)) then
        if (present(lsquare)) then
          distance =      sum(evr**2)
        else
          distance = sqrt(sum(evr**2))
        endif
      endif
!
      if (present(vector)) vector=evr
!
    endsubroutine get_particles_interdistance
!***********************************************************************
    subroutine remove_particle(fp,ipar,k,dfp,ineargrid,ks)
!
      real, dimension (mpar_loc,mparray) :: fp
      integer, dimension (mpar_loc) :: ipar
      integer :: k
      real, dimension (mpar_loc,mpvar), optional :: dfp
      integer, dimension (mpar_loc,3), optional :: ineargrid
      integer, optional :: ks
!
      logical :: lnbody
      real :: t_sp   ! t in single precision for backwards compatibility
!
      intent (inout) :: fp, dfp, ineargrid
      intent (in)    :: k, ks
!
      t_sp = t
!
!  Check that we are not removing massive particles.
!
      lnbody=(lparticles_nbody.and.any(ipar(k)==ipar_nbody))
!
      if (lnbody) then
        if (present(ks)) then
          print*, 'nbody particle ', ks
          print*, 'is removing the following nbody particle:'
        else
          print*, 'the following nbody particle is being removed'
        endif
        print*, 'ipar(k)=', ipar(k)
        print*, 'xp,yp,zp=' ,fp(k,ixp), fp(k,iyp), fp(k,izp)
        print*, 'vxp,vyp,vzp=', fp(k,ivpx), fp(k,ivpy), fp(k,ivpz)
        call fatal_error("remove_particle","are you sure this should happen?")
      endif
!
!  Write to the respective processor that the particle is removed.
!  We also write the time.
!
!  TODO: It would be better to write this information in binary format to avoid
!  conversion problems when reading t_rmv with pc_read_pvar.
!
      open(20,file=trim(directory)//'/rmv_ipar.dat',position='append')
      if (present(ks)) then
        write(20,*) ipar(k), t_sp, ipar(ks)
      else
        write(20,*) ipar(k), t_sp
      endif
      close(20)
!
      open(20,file=trim(directory)//'/rmv_par.dat', &
          position='append',form='unformatted')
      if (present(ks)) then
        write(20) fp(k,:), fp(ks,:)
      else
        write(20) fp(k,:)
      endif
      close(20)
!
      if (ip<=8) print*, 'removed particle ', ipar(k)
!
!  Switch the removed particle with the last particle present in the processor
!  npar_loc
!
      fp(k,:)=fp(npar_loc,:)
      if (present(dfp)) dfp(k,:)=dfp(npar_loc,:)
      if (present(ineargrid)) ineargrid(k,:)=ineargrid(npar_loc,:)
      ipar(k)=ipar(npar_loc)
      if (lparticles_blocks) inearblock(k)=inearblock(npar_loc)
!
!  Reduce the number of particles by one.
!
      npar_loc=npar_loc-1
!
    endsubroutine remove_particle
!***********************************************************************
    subroutine count_particles(ipar,npar_found)
!
      use Mpicomm, only: mpireduce_sum_int
!
      integer, dimension (mpar_loc) :: ipar
      integer :: npar_found
!
      npar_found=0
!
      call mpireduce_sum_int(npar_loc,npar_found)
      call keep_compiler_quiet(ipar)
!
    endsubroutine count_particles
!***********************************************************************
    subroutine output_particle_size_dist(fp)
!
!  Calculate size distribution of particles and output to file.
!
!   6-feb-11/anders: coded
!
      use Mpicomm, only: mpireduce_sum
!
      real, dimension (mpar_loc,mparray) :: fp
!
      real, dimension (nbin_ap_dist) :: log_ap_loc
      real, dimension (nbin_ap_dist) :: log_ap_loc_low, log_ap_loc_high
      real, dimension (nbin_ap_dist) :: rhop_dist, rhop_dist_sum
      real, save :: delta_log_ap
      integer :: i, k
      logical, save :: lfirstcall=.true.
      logical :: file_exists
!
      intent (in) :: fp
!
!  Define the bins for the size distribution and save to file.
!
      if (lfirstcall) then
        delta_log_ap=(log_ap_max_dist-log_ap_min_dist)/nbin_ap_dist
        do i=1,nbin_ap_dist
          log_ap_loc_low(i)=log_ap_min_dist+(i-1)*delta_log_ap
        enddo
        log_ap_loc_high = log_ap_loc_low + delta_log_ap
        log_ap_loc      = (log_ap_loc_low + log_ap_loc_high)/2
        if (lroot) then
          inquire(file=trim(datadir)//'/particle_size_dist.dat', &
              exist=file_exists)
          if (.not. file_exists) then
            open(20,file=trim(datadir)//'/particle_size_dist.dat', &
                status='new')
            write(20,*) log_ap_min_dist, log_ap_max_dist, nbin_ap_dist
            write(20,*) log_ap_loc
            write(20,*) log_ap_loc_low
            write(20,*) log_ap_loc_high
            close(20)
          endif
        endif
        lfirstcall=.false.
      endif
!
!  Loop over particles and add their mass to the radius bin.
!
      rhop_dist=0.0
      do k=1,npar_loc
        i=(alog10(fp(k,iap))-log_ap_min_dist)/delta_log_ap+1
        if (i>=1 .and. i<=nbin_ap_dist) then
          if (lparticles_number) then
            rhop_dist(i)=rhop_dist(i)+ &
                four_pi_rhopmat_over_three*fp(k,iap)**3*fp(k,inpswarm)
          else
            rhop_dist(i)=rhop_dist(i)+rhop_const
          endif
        endif
      enddo
!
!  Sum over all processors
!
      call mpireduce_sum(rhop_dist,rhop_dist_sum,nbin_ap_dist)
!
!  Save size distribution function to file.
!
      if (lroot) then
        open(20,file=trim(datadir)//'/particle_size_dist.dat', &
            position='append')
        write(20,*) t, rhop_dist_sum
        close(20)
      endif
!
    endsubroutine output_particle_size_dist
!***********************************************************************
    subroutine get_rhopswarm_ineargrid(mp_swarm_tmp,fp,k,ineark,rhop_swarm_tmp)
!
!  Subroutine to calculate rhop_swarm, the mass density of a single
!  superparticle. The fundamental quantity is actually mp_swarm, the
!  mass of a superparticle. From that one calculates rhop_swarm=mp_swarm/dV,
!  where dV is the volume of a cell. In an equidistant Cartesian grid
!  this is simply a constant, and set in the beginning of the code. In
!  polar and non-equidistant grids dV varies with position such that
!
!    dV = dVol_x(l) * dVol_y(m) * dVol_z(n)
!
!  This subroutine takes care of this variation, also ensuring that the
!  impact on equidistant Cartesian grids is minimal.
!
!  Retrieves a scalar.
!
!  29-apr-11/wlad: coded
!
      real, intent(in)  :: mp_swarm_tmp
      real, dimension (mpar_loc,mparray), intent(in) :: fp
      integer, intent(in) :: k
      integer, dimension (3), intent(in) :: ineark
      real, intent(out) :: rhop_swarm_tmp
!
      integer  :: il,im,in
!
      if (lcartesian_coords.and.all(lequidist)) then
        if (lparticles_density) then
          rhop_swarm_tmp = fp(k,irhopswarm)
        elseif (lparticles_radius.and.lparticles_number) then
          rhop_swarm_tmp = &
              four_pi_rhopmat_over_three*fp(k,iap)**3*fp(k,inpswarm)
        else
          rhop_swarm_tmp = rhop_swarm
        endif
      else
        il = ineark(1) ; im = ineark(2) ; in = ineark(3)
        rhop_swarm_tmp = mp_swarm_tmp*dVol1_x(il)*dVol1_y(im)*dVol1_z(in)
      endif
!
    endsubroutine get_rhopswarm_ineargrid
!***********************************************************************
    subroutine get_rhopswarm_point(mp_swarm_tmp,fp,k,il,im,in,rhop_swarm_tmp)
!
!  Same as get_rhopswarm_ineargrid, for general grid points il,im,in.
!  Retrieves a scalar.
!
!  29-apr-11/wlad: coded
!
      real, intent(in)  :: mp_swarm_tmp
      real, dimension (mpar_loc,mparray), intent(in) :: fp
      integer, intent(in) :: k, il, im, in
      real, intent(out) :: rhop_swarm_tmp
!
      if (lcartesian_coords.and.all(lequidist)) then
        if (lparticles_density) then
          rhop_swarm_tmp = fp(k,irhopswarm)
        elseif (lparticles_radius.and.lparticles_number) then
          rhop_swarm_tmp = &
              four_pi_rhopmat_over_three*fp(k,iap)**3*fp(k,inpswarm)
        else
          rhop_swarm_tmp = rhop_swarm
        endif
      else
        rhop_swarm_tmp = mp_swarm_tmp*dVol1_x(il)*dVol1_y(im)*dVol1_z(in)
      endif
!
    endsubroutine get_rhopswarm_point
!***********************************************************************
    subroutine get_rhopswarm_block(mp_swarm_tmp,fp,k,il,im,in,ib,rhop_swarm_tmp)
!
!  Same as get_rhopswarm_point, but for the volume elements as block arrays.
!  Retrieves a scalar.
!
!  29-apr-11/wlad: coded
!
      use Particles_mpicomm, only: dVol1xb, dVol1yb, dVol1zb
!
      real, intent(in) :: mp_swarm_tmp
      real, dimension (mpar_loc,mparray), intent(in) :: fp
      integer, intent(in) :: k, il, im, in, ib
      real, intent(out) :: rhop_swarm_tmp
!
      if (lcartesian_coords.and.all(lequidist)) then
        if (lparticles_density) then
          rhop_swarm_tmp = fp(k,irhopswarm)
        elseif (lparticles_radius.and.lparticles_number) then
          rhop_swarm_tmp = &
              four_pi_rhopmat_over_three*fp(k,iap)**3*fp(k,inpswarm)
        else
          rhop_swarm_tmp = rhop_swarm
        endif
      else
        rhop_swarm_tmp = mp_swarm_tmp*&
             dVol1xb(il,ib)*dVol1yb(im,ib)*dVol1zb(in,ib)
      endif
!
    endsubroutine get_rhopswarm_block
!***********************************************************************
    subroutine get_rhopswarm_pencil(mp_swarm_tmp,fp,k,im,in,rhop_swarm_tmp)
!
!  Same as get_rhopswarm_ineargrid, but retrieves a pencil.
!
!  29-apr-11/wlad: coded
!
      real, intent(in) :: mp_swarm_tmp
      real, dimension (mpar_loc,mparray), intent(in) :: fp
      integer, intent(in) :: k, im, in
      real, dimension(nx), intent(out) :: rhop_swarm_tmp
!
      if (lcartesian_coords.and.all(lequidist)) then
        if (lparticles_density) then
          rhop_swarm_tmp = fp(k,irhopswarm)
        elseif (lparticles_radius.and.lparticles_number) then
          rhop_swarm_tmp = &
              four_pi_rhopmat_over_three*fp(k,iap)**3*fp(k,inpswarm)
        else
          rhop_swarm_tmp = rhop_swarm
        endif
      else
        rhop_swarm_tmp = mp_swarm_tmp*dVol1_x(l1:l2)*dVol1_y(im)*dVol1_z(in)
      endif
!
    endsubroutine get_rhopswarm_pencil
!***********************************************************************
    subroutine find_grid_volume(ixx,iyy,izz,volume_cell)
!
!  Find the volume of the grid cell
!
!  24-sep-14/nils: coded
!
      real, intent(out) :: volume_cell
      integer, intent(in) :: ixx,iyy,izz
      real :: dx1, dy1, dz1
!
      if (nxgrid ==1) then
        dx1=1./Lxyz(1)
      else
        dx1=dx_1(ixx)
      endif
      if (nygrid ==1) then
        dy1=1./Lxyz(2)
      else
        dy1=dy_1(iyy)
      endif
      if (nzgrid ==1) then
        dz1=1./Lxyz(3)
      else
        dz1=dz_1(izz)
      endif
      volume_cell=1./(dx1*dy1*dz1)
!
    end subroutine find_grid_volume
!***********************************************************************
    subroutine find_interpolation_weight(weight,fp,k,ixx,iyy,izz,ix0,iy0,iz0)
!
      real :: weight
      real :: weight_x, weight_y, weight_z
      integer, intent(in) :: k,ixx,iyy,izz,ix0,iy0,iz0
      real, dimension (mpar_loc,mparray), intent(in) :: fp
! 
      if (lparticlemesh_cic) then
!
!  Cloud In Cell (CIC) scheme.
!
!  Particle influences the 8 surrounding grid points. The reference point is
!  the grid point at the lower left corner.
!
        weight=1.0
        if (nxgrid/=1) &
            weight=weight*( 1.0-abs(fp(k,ixp)-x(ixx))*dx_1(ixx) )
        if (nygrid/=1) &
            weight=weight*( 1.0-abs(fp(k,iyp)-y(iyy))*dy_1(iyy) )
        if (nzgrid/=1) &
            weight=weight*( 1.0-abs(fp(k,izp)-z(izz))*dz_1(izz) )
      elseif (lparticlemesh_tsc) then
!
!  Triangular Shaped Cloud (TSC) scheme.
!
!  Particle influences the 27 surrounding grid points, but has a density that
!  decreases with the distance from the particle centre.
!
!  The nearest grid point is influenced differently than the left and right
!  neighbours are. A particle that is situated exactly on a grid point gives
!  3/4 contribution to that grid point and 1/8 to each of the neighbours.
!
        if ( ((ixx-ix0)==-1) .or. ((ixx-ix0)==+1) ) then
          weight_x=1.125-1.5* abs(fp(k,ixp)-x(ixx))*dx_1(ixx) + &
              0.5*(abs(fp(k,ixp)-x(ixx))*dx_1(ixx))**2
        else
          if (nxgrid/=1) &
              weight_x=0.75-((fp(k,ixp)-x(ixx))*dx_1(ixx))**2
        endif
        if ( ((iyy-iy0)==-1) .or. ((iyy-iy0)==+1) ) then
          weight_y=1.125-1.5* abs(fp(k,iyp)-y(iyy))*dy_1(iyy) + &
              0.5*(abs(fp(k,iyp)-y(iyy))*dy_1(iyy))**2
        else
          if (nygrid/=1) &
              weight_y=0.75-((fp(k,iyp)-y(iyy))*dy_1(iyy))**2
        endif
        if ( ((izz-iz0)==-1) .or. ((izz-iz0)==+1) ) then
          weight_z=1.125-1.5* abs(fp(k,izp)-z(izz))*dz_1(izz) + &
              0.5*(abs(fp(k,izp)-z(izz))*dz_1(izz))**2
        else
          if (nzgrid/=1) &
              weight_z=0.75-((fp(k,izp)-z(izz))*dz_1(izz))**2
        endif
!
        weight=1.0
!
        if (nxgrid/=1) weight=weight*weight_x
        if (nygrid/=1) weight=weight*weight_y
        if (nzgrid/=1) weight=weight*weight_z
      elseif (lparticlemesh_gab) then
!
!  Gaussian box approach. The particles influence is distributed over 
!  the nearest grid point and 3 nodes in each dimension. The weighting of the 
!  source term follows a gaussian distribution
!
        weight = 1.
        if (nxgrid/=1) weight=weight*gab_weights(abs(ixx-ix0)+1)
        if (nygrid/=1) weight=weight*gab_weights(abs(iyy-iy0)+1)
        if (nzgrid/=1) weight=weight*gab_weights(abs(izz-iz0)+1)
      else
!
!  Nearest Grid Point (NGP) scheme.
!
        weight=1.
      endif
!
    end subroutine find_interpolation_weight
!***********************************************************************
    subroutine find_interpolation_indeces(ixx0,ixx1,iyy0,iyy1,izz0,izz1,&
        fp,k,ix0,iy0,iz0)
!
      integer, intent(in)  :: k,ix0,iy0,iz0
      integer, intent(out) :: ixx0,ixx1,iyy0,iyy1,izz0,izz1
      real, dimension (mpar_loc,mparray), intent(in) :: fp
!
!  Cloud In Cell (CIC) scheme.
!
      if (lparticlemesh_cic) then
        ixx0=ix0; iyy0=iy0; izz0=iz0
        ixx1=ix0; iyy1=iy0; izz1=iz0
!
!  Particle influences the 8 surrounding grid points. The reference point is
!  the grid point at the lower left corner.
!
        if ( (x(ix0)>fp(k,ixp)) .and. nxgrid/=1) ixx0=ixx0-1
        if ( (y(iy0)>fp(k,iyp)) .and. nygrid/=1) iyy0=iyy0-1
        if ( (z(iz0)>fp(k,izp)) .and. nzgrid/=1) izz0=izz0-1
        if (nxgrid/=1) ixx1=ixx0+1
        if (nygrid/=1) iyy1=iyy0+1
        if (nzgrid/=1) izz1=izz0+1
      elseif (lparticlemesh_tsc) then
!
!  Particle influences the 27 surrounding grid points, but has a density that
!  decreases with the distance from the particle centre.
!
        if (nxgrid/=1) then
          ixx0=ix0-1; ixx1=ix0+1
        else
          ixx0=ix0  ; ixx1=ix0
        endif
        if (nygrid/=1) then
          iyy0=iy0-1; iyy1=iy0+1
        else
          iyy0=iy0  ; iyy1=iy0
        endif
        if (nzgrid/=1) then
          izz0=iz0-1; izz1=iz0+1
        else
          izz0=iz0  ; izz1=iz0
        endif
      elseif (lparticlemesh_gab) then
!
!  Gaussian box approach. The particles influence is distributed over 
!  the nearest grid point and 3 nodes in each dimension, for a total
!  of 81 influenced points in 3 dimensions
!
        if (nxgrid/=1) then 
          ixx0=ix0-3 
          ixx1=ix0+3
        else
          ixx0=ix0
          ixx1=ix0
        endif
        if (nygrid/=1) then 
          iyy0=iy0-3 
          iyy1=iy0+3
        else
          iyy0=iy0
          iyy1=iy0
        endif
        if (nzgrid/=1) then 
          izz0=iz0-3 
          izz1=iz0+3
        else
          izz0=iz0
          izz1=iz0
        endif
      else
!
!  Nearest Grid Point (NGP) scheme.
!
        ixx0=ix0
        ixx1=ixx0
        iyy0=m
        iyy1=iyy0
        izz0=n
        izz1=izz0
      endif
!
    end subroutine find_interpolation_indeces
!***********************************************************************
    real function get_gas_density(f, ix, iy, iz) result(rho)
!
!  Reads the gas density at location (ix, iy, iz).
!
!  19-jun-14/ccyang: coded.
!
      use EquationOfState, only: get_stratz, rho0
      use DensityMethods , only: getrho_s
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      integer, intent(in) :: ix, iy, iz
!
      real, dimension(mz) :: rho0z = 0.0
      logical :: lfirstcall = .true.
!
!  Initialization
!
      init: if (lfirstcall) then
        if (lstratz) call get_stratz(z, rho0z)
        lfirstcall = .false.
      endif init
!
!  Find the gas density at (ix,iy,iz).
!
      if (lstratz) then
        rho = rho0z(iz) * (1.0 + f(ix,iy,iz,irho))
      elseif (ilnrho /= 0) then
        rho = getrho_s(f(ix,iy,iz,ilnrho), ix)
      else
        rho = rho0
      endif
!
    endfunction get_gas_density
!***********************************************************************
    subroutine precalc_cell_volumes(f)
!
      real, dimension (mx,my,mz,mfarray), intent(out) :: f
      integer :: k1, k2, k3
      logical :: l2d
!
      l2d = (((lcartesian_coords .or. lcylindrical_coords) .and. (nzgrid==1)) &
        .or. (lspherical_coords .and. nygrid==1))
      if (lcartesian_coords) then
        if (l2d) then
          f(:,:,:,ivol) = dx*dy
        else
          f(:,:,:,ivol) = dx*dy*dz
        endif
      elseif (lcylindrical_coords) then
        do k1=n1,n2
          do k2=m1,m2
            if (l2d) then
              f(:,k2,k1,ivol) = x*dy
            else
              f(:,k2,k1,ivol) = x*dx*dy*dz
            endif
          enddo
        enddo
      elseif (lspherical_coords) then
        do k1=n1,n2
          do k2=m1,m2
            do k3=l1,l2
              if (l2d) then
                f(k3,k2,k1,ivol) = x(k3)*dz
              else
                f(k3,k2,k1,ivol) = dx*dy*dz*sin(y(k2))*x(k3)**2.0
              endif
            enddo
          enddo
        enddo
      endif
    endsubroutine precalc_cell_volumes
!***********************************************************************
endmodule Particles_sub
