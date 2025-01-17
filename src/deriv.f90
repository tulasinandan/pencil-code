! $Id$
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM integer, parameter :: nghost = 3
!
!***************************************************************
module Deriv
!
  use Messages, only: fatal_error, warning
  use Cdata
!
  implicit none
!
  private
!
  public :: initialize_deriv, finalize_deriv
  public :: der, der2, der3, der4, der5, der6, derij, der5i1j, der5_single
  public :: der6_other, der_pencil, der2_pencil
  public :: deri_3d_inds
  public :: der_x,der2_x
  public :: der_z,der2_z
  public :: der_upwind1st
  public :: der_onesided_4_slice
  public :: der_onesided_4_slice_other
  public :: der2_minmod
  public :: heatflux_deriv_x
!
  real :: der2_coef0, der2_coef1, der2_coef2, der2_coef3
!
!debug  integer, parameter :: icount_der   = 1         !DERCOUNT
!debug  integer, parameter :: icount_der2  = 2         !DERCOUNT
!debug  integer, parameter :: icount_der4  = 3         !DERCOUNT
!debug  integer, parameter :: icount_der5  = 4         !DERCOUNT
!debug  integer, parameter :: icount_der6  = 5         !DERCOUNT
!debug  integer, parameter :: icount_derij = 6         !DERCOUNT
!debug  integer, parameter :: icount_der_upwind1st = 7 !DERCOUNT
!debug  integer, parameter :: icount_der_other = 8     !DERCOUNT
!
  interface der                 ! Overload the der function
    module procedure der_main   ! derivative of an 'mvar' variable
    module procedure der_other  ! derivative of another field
  endinterface
!
  interface der2                 ! Overload the der function
    module procedure der2_main   ! derivative of an 'mvar' variable
    module procedure der2_other  ! derivative of another field
  endinterface
!
  interface derij                 ! Overload the der function
    module procedure derij_main   ! derivative of an 'mvar' variable
    module procedure derij_other  ! derivative of another field
  endinterface
!
  interface  der_onesided_4_slice                ! Overload the der function
    module procedure  der_onesided_4_slice_main  ! derivative of an 'mvar' variable
    module procedure  der_onesided_4_slice_main_pt
    module procedure  der_onesided_4_slice_other ! derivative of another field
    module procedure  der_onesided_4_slice_other_pt
  endinterface
!
  contains
!
!***********************************************************************
    subroutine initialize_deriv()
!
!  Initialize stencil coefficients
!
      select case (der2_type)
!
      case ('standard')
        der2_coef0=-490./180.; der2_coef1=270./180.
        der2_coef2=-27./180.; der2_coef3=2./180.
!
      case ('tuned1')
        der2_coef0=-0.75; der2_coef1=0.34375
        der2_coef2=0.125; der2_coef3=-0.09375
!
      case default
        write(unit=errormsg,fmt=*) &
             "der2_type doesn't exist"
        call fatal_error('initialize_deriv',errormsg)
!
      endselect
!
    endsubroutine initialize_deriv
!***********************************************************************
    subroutine der_main(f, k, df, j, ignoredx)
!
!  calculate derivative df_k/dx_j
!  accurate to 6th order, explicit, periodic
!  replace cshifts by explicit construction -> x6.5 faster!
!
!   1-oct-97/axel: coded
!  18-jul-98/axel: corrected mx -> my and mx -> mz in all y and z ders
!   1-apr-01/axel+wolf: pencil formulation
!  25-jun-04/tobi+wolf: adapted for non-equidistant grids
!  21-feb-07/axel: added 1/r and 1/pomega factors for non-coord basis
!  20-sep-13/ccyang: added optional argument ignoredx
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      real, dimension(nx), intent(out) :: df
      integer, intent(in) :: j, k
      logical, intent(in), optional :: ignoredx
!
      real, parameter :: a = 1.0 / 60.0
      real, dimension(nx) :: fac
      logical :: withdx
!
!debug      if (loptimise_ders) der_call_count(k,icount_der,j,1) = & !DERCOUNT
!debug                            der_call_count(k,icount_der,j,1)+1 !DERCOUNT
!
      if (present(ignoredx)) then
        withdx = .not. ignoredx
        if (ignoredx) fac = a
      else
        withdx = .true.
      endif
!
      if (j==1) then
        if (nxgrid/=1) then
          if (withdx) fac = a * dx_1(l1:l2)
          df=fac*(+ 45.0*(f(l1+1:l2+1,m,n,k)-f(l1-1:l2-1,m,n,k)) &
                  -  9.0*(f(l1+2:l2+2,m,n,k)-f(l1-2:l2-2,m,n,k)) &
                  +      (f(l1+3:l2+3,m,n,k)-f(l1-3:l2-3,m,n,k)))
        else
          df=0.
          if (ip<=5) print*, 'der_main: Degenerate case in x-direction'
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          if (withdx) fac = a * dy_1(m)
          df=fac*(+ 45.0*(f(l1:l2,m+1,n,k)-f(l1:l2,m-1,n,k)) &
                  -  9.0*(f(l1:l2,m+2,n,k)-f(l1:l2,m-2,n,k)) &
                  +      (f(l1:l2,m+3,n,k)-f(l1:l2,m-3,n,k)))
          if (withdx .and. lspherical_coords  ) df = df * r1_mn
          if (withdx .and. lcylindrical_coords) df = df * rcyl_mn1
        else
          df=0.
          if (ip<=5) print*, 'der_main: Degenerate case in y-direction'
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          if (withdx) fac = a * dz_1(n)
          df=fac*(+ 45.0*(f(l1:l2,m,n+1,k)-f(l1:l2,m,n-1,k)) &
                  -  9.0*(f(l1:l2,m,n+2,k)-f(l1:l2,m,n-2,k)) &
                  +      (f(l1:l2,m,n+3,k)-f(l1:l2,m,n-3,k)))
          if (withdx .and. lspherical_coords) df = df * r1_mn * sin1th(m)
        else
          df=0.
          if (ip<=5) print*, 'der_main: Degenerate case in z-direction'
        endif
      endif
!
    endsubroutine der_main
!***********************************************************************
    subroutine der_x(f,df)
!
!  x derivative operating on an x-dependent 1-D array
!
!  23-jun-15/pete: adapted from der_z; note that f is not the f array!
!
      real, dimension (mx), intent(in)  :: f
      real, dimension (nx), intent(out) :: df
!
      real, dimension (nx) :: fac
!
      if (nxgrid/=1) then
        fac=(1./60)*dx_1(l1:l2)
        df=fac*(+ 45.0*(f(l1+1:l2+1)-f(l1-1:l2-1)) &
                -  9.0*(f(l1+2:l2+2)-f(l1-2:l2-2)) &
                +      (f(l1+3:l2+3)-f(l1-3:l2-3)))
      else
        df=0.
        if (ip<=5) print*, 'der_x: Degenerate case in x-direction'
      endif
!
    endsubroutine der_x
!***********************************************************************
    subroutine der2_x(f,df2)
!
!  Second x derivative operating on an x-dependent 1-D array
!
!  23-jun-15/pete: adapted from der2_z
!
      real, dimension (mx), intent(in)  :: f
      real, dimension (nx), intent(out) :: df2
!
      real, dimension (nx) :: fac
!
      if (nxgrid/=1) then
        fac=(1./180)*dx_1(l1:l2)**2
        df2=fac*(-490.0*f(l1:l2) &
                 +270.0*(f(l1+1:l2+1)+f(l1-1:l2-1)) &
                 - 27.0*(f(l1+2:l2+2)+f(l1-2:l2-2)) &
                 +  2.0*(f(l1+3:l2+3)+f(l1-3:l2-3)))
      else
        df2=0.
        if (ip<=5) print*, 'der2_x: Degenerate case in x-direction'
      endif
!
    endsubroutine der2_x
!***********************************************************************
    subroutine der_z(f,df)
!
!  z derivative operating on a z-dependent 1-D array
!
!   9-feb-07/axel: adapted from der_main; note that f is not the f array!
!
      real, dimension (mz), intent(in)  :: f
      real, dimension (nz), intent(out) :: df
!
      real, dimension (nz) :: fac
!
      if (nzgrid/=1) then
        fac=(1./60)*dz_1(n1:n2)
        df=fac*(+ 45.0*(f(n1+1:n2+1)-f(n1-1:n2-1)) &
                -  9.0*(f(n1+2:n2+2)-f(n1-2:n2-2)) &
                +      (f(n1+3:n2+3)-f(n1-3:n2-3)))
      else
        df=0.
        if (ip<=5) print*, 'der_z: Degenerate case in z-direction'
      endif
!
    endsubroutine der_z
!***********************************************************************
    subroutine der2_z(f,df2)
!
!  z derivative operating on a z-dependent 1-D array
!
!   2-jan-10/axel: adapted from der_z and der_main
!
      real, dimension (mz), intent(in)  :: f
      real, dimension (nz), intent(out) :: df2
!
      real, dimension (nz) :: fac
!
      if (nzgrid/=1) then
        fac=(1./180)*dz_1(n1:n2)**2
        df2=fac*(-490.0*f(n1:n2) &
                 +270.0*(f(n1+1:n2+1)+f(n1-1:n2-1)) &
                 - 27.0*(f(n1+2:n2+2)+f(n1-2:n2-2)) &
                 +  2.0*(f(n1+3:n2+3)+f(n1-3:n2-3)))
      else
        df2=0.
        if (ip<=5) print*, 'der2_z: Degenerate case in z-direction'
      endif
!
    endsubroutine der2_z
!***********************************************************************
    subroutine der_other(f,df,j)
!
!  Along one pencil in NON f variable
!  calculate derivative of a scalar, get scalar
!  accurate to 6th order, explicit, periodic
!  replace cshifts by explicit construction -> x6.5 faster!
!
!  26-nov-02/tony: coded - duplicate der_main but without k subscript
!                          then overload the der interface.
!  25-jun-04/tobi+wolf: adapted for non-equidistant grids
!  21-feb-07/axel: added 1/r and 1/pomega factors for non-coord basis
!
      real, dimension (mx,my,mz) :: f
      real, dimension (nx) :: df,fac
      integer :: j
!
      intent(in)  :: f,j
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(1,icount_der_other,j,1) = &
!debug                          der_call_count(1,icount_der_other,j,1) + 1
!
      if (j==1) then
        if (nxgrid/=1) then
          fac=(1./60)*dx_1(l1:l2)
          df=fac*(+ 45.0*(f(l1+1:l2+1,m,n)-f(l1-1:l2-1,m,n)) &
                  -  9.0*(f(l1+2:l2+2,m,n)-f(l1-2:l2-2,m,n)) &
                  +      (f(l1+3:l2+3,m,n)-f(l1-3:l2-3,m,n)))
        else
          df=0.
          if (ip<=5) print*, 'der_other: Degenerate case in x-direction'
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          fac=(1./60)*dy_1(m)
          df=fac*(+ 45.0*(f(l1:l2,m+1,n)-f(l1:l2,m-1,n)) &
                  -  9.0*(f(l1:l2,m+2,n)-f(l1:l2,m-2,n)) &
                  +      (f(l1:l2,m+3,n)-f(l1:l2,m-3,n)))
          if (lspherical_coords)     df=df*r1_mn
          if (lcylindrical_coords)   df=df*rcyl_mn1
        else
          df=0.
          if (ip<=5) print*, 'der_other: Degenerate case in y-direction'
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          fac=(1./60)*dz_1(n)
          df=fac*(+ 45.0*(f(l1:l2,m,n+1)-f(l1:l2,m,n-1)) &
                  -  9.0*(f(l1:l2,m,n+2)-f(l1:l2,m,n-2)) &
                  +      (f(l1:l2,m,n+3)-f(l1:l2,m,n-3)))
          if (lspherical_coords) df=df*r1_mn*sin1th(m)
        else
          df=0.
          if (ip<=5) print*, 'der_other: Degenerate case in z-direction'
        endif
      endif
!
    endsubroutine der_other
!***********************************************************************
    subroutine der_pencil(j,pencil,df)
!
!  Calculate first derivative of any x, y or z pencil.
!
!  01-nov-07/anders: adapted from der
!
      real, dimension (:) :: pencil,df
      integer :: j
!
      intent(in)  :: j, pencil
      intent(out) :: df
!
!  x-derivative
!
      if (j==1) then
        if (size(pencil)/=mx) then
          if (lroot) print*, 'der_pencil: pencil must be of size mx for x derivative'
          call fatal_error('der_pencil','')
        endif
        df(l1:l2)=(1./60)*dx_1(l1:l2)*( &
            + 45.0*(pencil(l1+1:l2+1)-pencil(l1-1:l2-1)) &
            -  9.0*(pencil(l1+2:l2+2)-pencil(l1-2:l2-2)) &
            +      (pencil(l1+3:l2+3)-pencil(l1-3:l2-3)))
      else if (j==2) then
!
!  y-derivative
!
        if (size(pencil)/=my) then
          if (lroot) print*, 'der_pencil: pencil must be of size my for y derivative'
          call fatal_error('der_pencil','')
        endif
        df(m1:m2)=(1./60)*dy_1(m1:m2)*( &
            + 45.0*(pencil(m1+1:m2+1)-pencil(m1-1:m2-1)) &
            -  9.0*(pencil(m1+2:m2+2)-pencil(m1-2:m2-2)) &
            +      (pencil(m1+3:m2+3)-pencil(m1-3:m2-3)))
      else if (j==3) then
!
!  z-derivative
!
        if (size(pencil)/=mz) then
          if (lroot) print*, 'der_pencil: pencil must be of size mz for z derivative'
          call fatal_error('der_pencil','')
        endif
        df(n1:n2)=(1./60)*dz_1(n1:n2)*( &
            + 45.0*(pencil(n1+1:n2+1)-pencil(n1-1:n2-1)) &
            -  9.0*(pencil(n1+2:n2+2)-pencil(n1-2:n2-2)) &
            +      (pencil(n1+3:n2+3)-pencil(n1-3:n2-3)))
      else
        if (lroot) print*, 'der_pencil: no such direction j=', j
        call fatal_error('der_pencil','')
      endif
!
      if (lcylindrical_coords.or.lspherical_coords) &
           call fatal_error("der_pencil","Not implemented for non-cartesian")
!
    endsubroutine der_pencil
!***********************************************************************
    subroutine der2_main(f,k,df2,j)
!
!  calculate 2nd derivative d^2f_k/dx_j^2
!  accurate to 6th order, explicit, periodic
!  replace cshifts by explicit construction -> x6.5 faster!
!
!   1-oct-97/axel: coded
!   1-apr-01/axel+wolf: pencil formulation
!  25-jun-04/tobi+wolf: adapted for non-equidistant grids
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df2,fac,df
      integer :: j,k
!
      intent(in)  :: f,k,j
      intent(out) :: df2
!
!debug      if (loptimise_ders) der_call_count(k,icount_der2,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der2,j,1) + 1 !DERCOUNT
!
      if (j==1) then
        if (nxgrid/=1) then
          fac=dx_1(l1:l2)**2
          df2=fac*(der2_coef0* f(l1  :l2  ,m,n,k) &
                  +der2_coef1*(f(l1+1:l2+1,m,n,k)+f(l1-1:l2-1,m,n,k)) &
                  +der2_coef2*(f(l1+2:l2+2,m,n,k)+f(l1-2:l2-2,m,n,k)) &
                  +der2_coef3*(f(l1+3:l2+3,m,n,k)+f(l1-3:l2-3,m,n,k)))
          if (.not.lequidist(j)) then
            call der(f,k,df,j)
            df2=df2+dx_tilde(l1:l2)*df
          endif
        else
          df2=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          fac=dy_1(m)**2
          df2=fac*(der2_coef0* f(l1:l2,m  ,n,k) &
                  +der2_coef1*(f(l1:l2,m+1,n,k)+f(l1:l2,m-1,n,k)) &
                  +der2_coef2*(f(l1:l2,m+2,n,k)+f(l1:l2,m-2,n,k)) &
                  +der2_coef3*(f(l1:l2,m+3,n,k)+f(l1:l2,m-3,n,k)))
          if (lspherical_coords)     df2=df2*r2_mn
          if (lcylindrical_coords)   df2=df2*rcyl_mn2
          if (.not.lequidist(j)) then
            call der(f,k,df,j)
            df2=df2+dy_tilde(m)*df
          endif
        else
          df2=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          fac=dz_1(n)**2
          df2=fac*( der2_coef0* f(l1:l2,m,n  ,k) &
                   +der2_coef1*(f(l1:l2,m,n+1,k)+f(l1:l2,m,n-1,k)) &
                   +der2_coef2*(f(l1:l2,m,n+2,k)+f(l1:l2,m,n-2,k)) &
                   +der2_coef3*(f(l1:l2,m,n+3,k)+f(l1:l2,m,n-3,k)))
          if (lspherical_coords) df2=df2*r2_mn*sin2th(m)
          if (.not.lequidist(j)) then
            call der(f,k,df,j)
            df2=df2+dz_tilde(n)*df
          endif
        else
          df2=0.
        endif
      endif
!
    endsubroutine der2_main
!***********************************************************************
    subroutine der2_other(f,df2,j)
!
!  calculate 2nd derivative d^2f/dx_j^2 (of scalar f)
!  accurate to 6th order, explicit, periodic
!  replace cshifts by explicit construction -> x6.5 faster!
!
!   1-oct-97/axel: coded
!   1-apr-01/axel+wolf: pencil formulation
!  25-jun-04/tobi+wolf: adapted for non-equidistant grids
!
      real, dimension (mx,my,mz) :: f
      real, dimension (nx) :: df2,fac,df
      integer :: j
!
      intent(in)  :: f,j
      intent(out) :: df2
!
!debug      if (loptimise_ders) der_call_count(k,icount_der2,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der2,j,1) + 1 !DERCOUNT
!
!
      if (j==1) then
        if (nxgrid/=1) then
          fac=(1./180)*dx_1(l1:l2)**2
          df2=fac*(-490.0*f(l1:l2,m,n) &
                   +270.0*(f(l1+1:l2+1,m,n)+f(l1-1:l2-1,m,n)) &
                   - 27.0*(f(l1+2:l2+2,m,n)+f(l1-2:l2-2,m,n)) &
                   +  2.0*(f(l1+3:l2+3,m,n)+f(l1-3:l2-3,m,n)))
          if (.not.lequidist(j)) then
            call der(f,df,j)
            df2=df2+dx_tilde(l1:l2)*df
          endif
        else
          df2=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          fac=(1./180)*dy_1(m)**2
          df2=fac*(-490.0*f(l1:l2,m,n) &
                   +270.0*(f(l1:l2,m+1,n)+f(l1:l2,m-1,n)) &
                   - 27.0*(f(l1:l2,m+2,n)+f(l1:l2,m-2,n)) &
                   +  2.0*(f(l1:l2,m+3,n)+f(l1:l2,m-3,n)))
          if (lspherical_coords)     df2=df2*r2_mn
          if (lcylindrical_coords)   df2=df2*rcyl_mn2
          if (.not.lequidist(j)) then
            call der(f,df,j)
            df2=df2+dy_tilde(m)*df
          endif
        else
          df2=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          fac=(1./180)*dz_1(n)**2
          df2=fac*(-490.0*f(l1:l2,m,n) &
                   +270.0*(f(l1:l2,m,n+1)+f(l1:l2,m,n-1)) &
                   - 27.0*(f(l1:l2,m,n+2)+f(l1:l2,m,n-2)) &
                   +  2.0*(f(l1:l2,m,n+3)+f(l1:l2,m,n-3)))
          if (lspherical_coords) df2=df2*r2_mn*sin2th(m)
          if (.not.lequidist(j)) then
            call der(f,df,j)
            df2=df2+dz_tilde(n)*df
          endif
        else
          df2=0.
        endif
      endif
!
    endsubroutine der2_other
!***********************************************************************
    subroutine der2_pencil(j,pencil,df2)
!
!  Calculate 2nd derivative of any x, y or z pencil.
!
!  01-nov-07/anders: adapted from der2
!
      real, dimension (:) :: pencil,df2
      integer :: j
!
      intent(in)  :: j, pencil
      intent(out) :: df2
!
!  x-derivative
!
      if (j==1) then
        if (size(pencil)/=mx) then
          if (lroot) print*, 'der2_pencil: pencil must be of size mx for x derivative'
          call fatal_error('der2_pencil','')
        endif
        df2=(1./180)*dx_1(l1:l2)**2*(-490.0*pencil(l1:l2) &
               +270.0*(pencil(l1+1:l2+1)+pencil(l1-1:l2-1)) &
               - 27.0*(pencil(l1+2:l2+2)+pencil(l1-2:l2-2)) &
               +  2.0*(pencil(l1+3:l2+3)+pencil(l1-3:l2-3)))
      else if (j==2) then
!
!  y-derivative
!
        if (size(pencil)/=my) then
          if (lroot) &
              print*, 'der2_pencil: pencil must be of size my for y derivative'
          call fatal_error('der2_pencil','')
        endif
        df2=(1./180)*dy_1(m1:m2)**2*(-490.0*pencil(m1:m2) &
               +270.0*(pencil(m1+1:m2+1)+pencil(m1-1:m2-1)) &
               - 27.0*(pencil(m1+2:m2+2)+pencil(m1-2:m2-2)) &
               +  2.0*(pencil(m1+3:m2+3)+pencil(m1-3:m2-3)))
      else if (j==3) then
!
!  z-derivative
!
        if (size(pencil)/=mz) then
          if (lroot) &
              print*, 'der2_pencil: pencil must be of size mz for z derivative'
          call fatal_error('der2_pencil','')
        endif
        df2=(1./180)*dz_1(n1:n2)**2*(-490.0*pencil(n1:n2) &
               +270.0*(pencil(n1+1:n2+1)+pencil(n1-1:n2-1)) &
               - 27.0*(pencil(n1+2:n2+2)+pencil(n1-2:n2-2)) &
               +  2.0*(pencil(n1+3:n2+3)+pencil(n1-3:n2-3)))
      else
        if (lroot) print*, 'der2_pencil: no such direction j=', j
        call fatal_error('der2_pencil','')
      endif
!
    endsubroutine der2_pencil
!***********************************************************************
    subroutine der3(f,k,df,j,ignoredx)
!
!  Calculate 3rd derivative of a scalar, get scalar
!
!  10-feb-06/anders: adapted from der5
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df,fac
      integer :: j,k
      logical, optional :: ignoredx
      logical :: igndx
!
      intent(in)  :: f,k,j,ignoredx
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_der5,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der5,j,1) + 1 !DERCOUNT
!
      if (present(ignoredx)) then
        igndx = ignoredx
      else
        igndx = .false.
      endif
!
      if (.not. lequidist(j)) &
          call fatal_error('der3','NOT IMPLEMENTED for non-equidistant grid')
!
      if (lspherical_coords) &
           call fatal_error('der3','NOT IMPLEMENTED for spherical coordinates')
!
      if (j==1) then
        if (nxgrid/=1) then
          if (igndx) then
            fac=(1.0/8)
          else
            fac=(1.0/8)*1./dx**3
          endif
          df=fac*(- 13.0*(f(l1+1:l2+1,m,n,k)-f(l1-1:l2-1,m,n,k)) &
                  +  8.0*(f(l1+2:l2+2,m,n,k)-f(l1-2:l2-2,m,n,k)) &
                  -  1.0*(f(l1+3:l2+3,m,n,k)-f(l1-3:l2-3,m,n,k)))
        else
          df=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          if (igndx) then
            fac=(1.0/8)
          else
            fac=(1.0/8)*1./dy**3
          endif
          df=fac*(- 13.0*(f(l1:l2,m+1,n,k)-f(l1:l2,m-1,n,k)) &
                  +  8.0*(f(l1:l2,m+2,n,k)-f(l1:l2,m-2,n,k)) &
                  -  1.0*(f(l1:l2,m+3,n,k)-f(l1:l2,m-3,n,k)))
          if (lcylindrical_coords)   df=df*rcyl_mn1**3
        else
          df=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          if (igndx) then
            fac=(1.0/8)
          else
            fac=(1.0/8)*1./dz**3
          endif
          df=fac*(- 13.0*(f(l1:l2,m,n+1,k)-f(l1:l2,m,n-1,k)) &
                  +  8.0*(f(l1:l2,m,n+2,k)-f(l1:l2,m,n-2,k)) &
                  -  1.0*(f(l1:l2,m,n+3,k)-f(l1:l2,m,n-3,k)))
        else
          df=0.
        endif
      endif
!
    endsubroutine der3
!***********************************************************************
    subroutine der4(f,k,df,j,ignoredx,upwind)
!
!  Calculate 4th derivative of a scalar, get scalar
!    Used for hyperdiffusion that affects small wave numbers as little as
!  possible (useful for density).
!    The optional flag IGNOREDX is useful for numerical purposes, where
!  you want to affect the Nyquist scale in each direction, independent of
!  the ratios dx:dy:dz.
!
!   8-jul-02/wolf: coded
!   9-dec-03/nils: adapted from der6
!  10-feb-06/anders: corrected sign and factor
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df
      real :: fac
      integer :: j,k
      logical, optional :: ignoredx,upwind
      logical :: igndx
!
      intent(in)  :: f,k,j,ignoredx,upwind
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_der4,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der4,j,1) + 1 !DERCOUNT
!
      if (lspherical_coords) &
           call fatal_error('der4','NOT IMPLEMENTED for spherical coordinates')
!
      if (present(ignoredx)) then
        igndx = ignoredx
      else
        if (.not. lequidist(j)) &
            call fatal_error('der4','non-equidistant grid works only with IGNOREDX')
        igndx = .false.
      endif
!
      if (present(upwind)) &
        call warning('der4','upwinding not implemented')
!
      if (j==1) then
        if (nxgrid/=1) then
          if (igndx) then
            fac=(1.0/6)
          else
            fac=(1.0/6)*1/dx**4
          endif
          df=fac*(+ 56.0* f(l1:l2,m,n,k) &
                  - 39.0*(f(l1+1:l2+1,m,n,k)+f(l1-1:l2-1,m,n,k)) &
                  + 12.0*(f(l1+2:l2+2,m,n,k)+f(l1-2:l2-2,m,n,k)) &
                  -      (f(l1+3:l2+3,m,n,k)+f(l1-3:l2-3,m,n,k)))
        else
          df=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          if (igndx) then
            fac=(1.0/6)
          else
            fac=(1.0/6)*1/dy**4
          endif
          df=fac*(+ 56.0* f(l1:l2,m  ,n,k) &
                  - 39.0*(f(l1:l2,m+1,n,k)+f(l1:l2,m-1,n,k)) &
                  + 12.0*(f(l1:l2,m+2,n,k)+f(l1:l2,m-2,n,k)) &
                  -      (f(l1:l2,m+3,n,k)+f(l1:l2,m-3,n,k)))
          if (lcylindrical_coords)   df=df*rcyl_mn1**4
        else
          df=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          if (igndx) then
            fac=(1.0/6)
          else
            fac=(1.0/6)*1/dz**4
          endif
          df=fac*(+ 56.0* f(l1:l2,m,n  ,k) &
                  - 39.0*(f(l1:l2,m,n+1,k)+f(l1:l2,m,n-1,k)) &
                  + 12.0*(f(l1:l2,m,n+2,k)+f(l1:l2,m,n-2,k)) &
                  -      (f(l1:l2,m,n+3,k)+f(l1:l2,m,n-3,k)))
        else
          df=0.
        endif
      endif
!
    endsubroutine der4
!***********************************************************************
    subroutine der5(f,k,df,j,ignoredx)
!
!  Calculate 5th derivative of a scalar, get scalar
!    Used for hyperdiffusion that affects small wave numbers as little as
!  possible (useful for density).
!    The optional flag IGNOREDX is useful for numerical purposes, where
!  you want to affect the Nyquist scale in each direction, independent of
!  the ratios dx:dy:dz.
!
!  29-oct-04/anders: adapted from der6
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df,fac
      integer :: j,k
      logical, optional :: ignoredx
      logical :: igndx
!
      intent(in)  :: f,k,j,ignoredx
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_der5,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der5,j,1) + 1 !DERCOUNT
!
      if (present(ignoredx)) then
        igndx = ignoredx
      else
        igndx = .false.
      endif
!
      if (.not. lequidist(j)) &
          call fatal_error('der5','NOT IMPLEMENTED for non-equidistant grid')
!
      if (lspherical_coords) &
           call fatal_error('der5','NOT IMPLEMENTED for spherical coordinates')
!
      if (j==1) then
        if (nxgrid/=1) then
          if (igndx) then
            fac=1.0
          else
            fac=1/dx**5
          endif
          df=fac*(+  2.5*(f(l1+1:l2+1,m,n,k)-f(l1-1:l2-1,m,n,k)) &
                  -  2.0*(f(l1+2:l2+2,m,n,k)-f(l1-2:l2-2,m,n,k)) &
                  +  0.5*(f(l1+3:l2+3,m,n,k)-f(l1-3:l2-3,m,n,k)))
        else
          df=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          if (igndx) then
            fac=1.0
          else
            fac=1/dy**5
          endif
          df=fac*(+  2.5*(f(l1:l2,m+1,n,k)-f(l1:l2,m-1,n,k)) &
                  -  2.0*(f(l1:l2,m+2,n,k)-f(l1:l2,m-2,n,k)) &
                  +  0.5*(f(l1:l2,m+3,n,k)-f(l1:l2,m-3,n,k)))
          if (lcylindrical_coords)   df=df*rcyl_mn1**5
        else
          df=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          if (igndx) then
            fac=1.0
          else
            fac=1/dz**5
          endif
          df=fac*(+  2.5*(f(l1:l2,m,n+1,k)-f(l1:l2,m,n-1,k)) &
                  -  2.0*(f(l1:l2,m,n+2,k)-f(l1:l2,m,n-2,k)) &
                  +  0.5*(f(l1:l2,m,n+3,k)-f(l1:l2,m,n-3,k)))
        else
          df=0.
        endif
      endif
!
    endsubroutine der5
!***********************************************************************
    subroutine der6(f,k,df,j,ignoredx,upwind)
!
!  Calculate 6th derivative of a scalar, get scalar
!    Used for hyperdiffusion that affects small wave numbers as little as
!  possible (useful for density).
!    The optional flag IGNOREDX is useful for numerical purposes, where
!  you want to affect the Nyquist scale in each direction, independent of
!  the ratios dx:dy:dz.
!    The optional flag UPWIND is a variant thereof, which calculates
!  D^(6)*dx^5/60, which is the upwind correction of centered derivatives.
!
!   8-jul-02/wolf: coded
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df,fac
      integer :: j,k
      logical, optional :: ignoredx,upwind
      logical :: igndx,upwnd
!
      intent(in)  :: f,k,j,ignoredx,upwind
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_der6,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der6,j,1) + 1 !DERCOUNT
!
      if (present(ignoredx)) then
        igndx = ignoredx
      else
        if (.not. lequidist(j)) then
          call fatal_error('der6','for non-equidistant grid only '//&
              'if dx is ignored.')
        endif
        igndx = .false.
      endif
!
      if (present(upwind)) then
        if (.not. lequidist(j)) then
          call fatal_error('der6','upwind cannot be used with '//&
              'non-equidistant grid.')
        endif
        upwnd = upwind
      else
        upwnd = .false.
!        if ((.not.lcartesian_coords).and.(.not.igndx)) then
!DM: non cartesian grids should not necessarily use upwinding. Wlad do you disagree ?
!         if (.not.igndx) then
!          call fatal_error('der6','in non-cartesian coordinates '//&
!              'just works if upwinding is used')
!        endif
      endif
!
      if (j==1) then
        if (nxgrid/=1) then
          if (igndx) then
            fac=1.
          else if (upwnd) then
            fac=(1.0/60)*dx_1(l1:l2)
          else
            fac=dx_1(l1:l2)**6
          endif
          df=fac*(- 20.0* f(l1:l2,m,n,k) &
                  + 15.0*(f(l1+1:l2+1,m,n,k)+f(l1-1:l2-1,m,n,k)) &
                  -  6.0*(f(l1+2:l2+2,m,n,k)+f(l1-2:l2-2,m,n,k)) &
                  +      (f(l1+3:l2+3,m,n,k)+f(l1-3:l2-3,m,n,k)))
        else
          df=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          if (igndx) then
            fac=1.
          else if (upwnd) then
            fac=(1.0/60)*dy_1(m)
          else
            fac=dy_1(m)**6
          endif
          df=fac*(- 20.0* f(l1:l2,m  ,n,k) &
                  + 15.0*(f(l1:l2,m+1,n,k)+f(l1:l2,m-1,n,k)) &
                  -  6.0*(f(l1:l2,m+2,n,k)+f(l1:l2,m-2,n,k)) &
                  +      (f(l1:l2,m+3,n,k)+f(l1:l2,m-3,n,k)))
        else
          df=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          if (igndx) then
            fac=1.
          else if (upwnd) then
            fac=(1.0/60)*dz_1(n)
          else
            fac=dz_1(n)**6
          endif
          df=fac*(- 20.0* f(l1:l2,m,n  ,k) &
                  + 15.0*(f(l1:l2,m,n+1,k)+f(l1:l2,m,n-1,k)) &
                  -  6.0*(f(l1:l2,m,n+2,k)+f(l1:l2,m,n-2,k)) &
                  +      (f(l1:l2,m,n+3,k)+f(l1:l2,m,n-3,k)))
        else
          df=0.
        endif
      endif
!
    endsubroutine der6
!***********************************************************************
    subroutine der2_minmod(f,j,delfk,delfkp1,delfkm1,k)
!
! Calculates gradient of a scalar along the direction j but
! get for the derivatives at the point i-1,i,i+1
!
      intent(in) :: f,k,j
      intent(out) :: delfk,delfkp1,delfkm1
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: delfk,delfkp1,delfkm1,fac
      real, dimension (nx,-1:1) :: delf
      real, dimension (0:nx+1) :: delfx
      integer :: j,k
      integer :: i,ii,ix
      real :: tmp1,tmp2,tmp3
! x-component
      select case (k)
        case(1)
          do i=l1-1,l2+1
            ix=i-nghost
            tmp1=f(i,m,n,j)-f(i-1,m,n,j)
            tmp2=(f(i+1,m,n,j)-f(i-1,m,n,j))/4.
            tmp3=f(i+1,m,n,j)-f(i,m,n,j)
            delfx(ix) = minmod(tmp1,tmp2,tmp3)
          enddo
          do i=1,nx;do ii=-1,1
            delf(i,ii) = delfx(i+ii)
          enddo;enddo
          fac = dx_1(l1:l2)
! y-component
        case(2)
          do i=l1,l2
            ix=i-nghost
            do ii=-1,1
              tmp1=f(i,m+ii,n,j)-f(i,m+ii-1,n,j)
              tmp2=(f(i,m+ii+1,n,j)-f(i,m+ii-1,n,j))/4.
              tmp3=f(i,m+ii+1,n,j)-f(i,m+ii,n,j)
              delf(ix,ii) = minmod(tmp1,tmp2,tmp3)*dy_1(i)
            enddo
          enddo
          fac = dy_1(m)
          if (lspherical_coords) fac = fac*r1_mn
          if (lcylindrical_coords) fac = fac*rcyl_mn1
! z-component
        case(3)
          do i=l1,l2
            ix=i-nghost
            do ii=-1,1
              tmp1=f(i,m,n+ii,j)-f(i,m,n+ii-1,j)
              tmp2=(f(i,m,n+ii+1,j)-f(i,m,n+ii-1,j))/4.
              tmp3=f(i,m,n+ii+1,j)-f(i,m,n+ii,j)
              delf(ix,ii) = minmod(tmp1,tmp2,tmp3)
            enddo
          enddo
          fac = dz_1(n)
          if (lspherical_coords) fac = fac*r1_mn*sin1th(m)
        case default
          call fatal_error('deriv:der2_minmod','wrong component')
        endselect
        delfkm1(:) = delf(:,-1)*fac
        delfk(:) = delf(:,0)*fac
        delfkp1(:) = delf(:,1)*fac
!
    endsubroutine der2_minmod
!***********************************************************************
    real function minmod(a,b,c)
!
!  DOCUMENT ME!
!
      real :: a,b,c
!
      if (((a>0) .and. (b>0) .and. (c>0))) then
        minmod=max(a,b,c)
      elseif (((a<0) .and. (b<0) .and. (c<0))) then
        minmod=min(a,b,c)
      else
        minmod=0.0
      endif
!
    endfunction minmod
!***********************************************************************
    subroutine der6_other(f,df,j,ignoredx,upwind)
!
!  Calculate 6th derivative of a scalar, get scalar
!    Used for hyperdiffusion that affects small wave numbers as little as
!  possible (useful for density).
!    The optional flag IGNOREDX is useful for numerical purposes, where
!  you want to affect the Nyquist scale in each direction, independent of
!  the ratios dx:dy:dz.
!    The optional flag UPWIND is a variant thereof, which calculates
!  D^(6)*dx^5/60, which is the upwind correction of centered derivatives.
!
!   8-jul-02/wolf: coded
!
      real, dimension (mx,my,mz) :: f
      real, dimension (nx) :: df,fac
      integer :: j
      logical, optional :: ignoredx,upwind
      logical :: igndx,upwnd
!
      intent(in)  :: f,j,ignoredx,upwind
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_der6,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der6,j,1) + 1 !DERCOUNT
!
      if (present(ignoredx)) then
        igndx = ignoredx
      else
        igndx = .false.
      endif
      if (present(upwind)) then
        upwnd = upwind
      else
        upwnd = .false.
        if (.not. lequidist(j)) &
             call fatal_error('der6_other','NOT IMPLEMENTED for '//&
             'non equidistant grid')
        if (.not.lcartesian_coords) &
             call fatal_error('der6_other','in non-cartesian coordinates '//&
             'just works if upwinding is used')
      endif
!
      if (j==1) then
        if (nxgrid/=1) then
          if (igndx) then
            fac=1.
          else if (upwnd) then
            fac=(1.0/60)*dx_1(l1:l2)
          else
            fac=1/dx**6
          endif
          df=fac*(- 20.0* f(l1:l2,m,n) &
                  + 15.0*(f(l1+1:l2+1,m,n)+f(l1-1:l2-1,m,n)) &
                  -  6.0*(f(l1+2:l2+2,m,n)+f(l1-2:l2-2,m,n)) &
                  +      (f(l1+3:l2+3,m,n)+f(l1-3:l2-3,m,n)))
        else
          df=0.
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          if (igndx) then
            fac=1.
          else if (upwnd) then
            fac=(1.0/60)*dy_1(m)
          else
            fac=1/dy**6
          endif
          df=fac*(- 20.0* f(l1:l2,m  ,n) &
                  + 15.0*(f(l1:l2,m+1,n)+f(l1:l2,m-1,n)) &
                  -  6.0*(f(l1:l2,m+2,n)+f(l1:l2,m-2,n)) &
                  +      (f(l1:l2,m+3,n)+f(l1:l2,m-3,n)))
        else
          df=0.
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          if (igndx) then
            fac=1.
          else if (upwnd) then
            fac=(1.0/60)*dz_1(n)
          else
            fac=1/dz**6
          endif
          df=fac*(- 20.0* f(l1:l2,m,n  ) &
                  + 15.0*(f(l1:l2,m,n+1)+f(l1:l2,m,n-1)) &
                  -  6.0*(f(l1:l2,m,n+2)+f(l1:l2,m,n-2)) &
                  +      (f(l1:l2,m,n+3)+f(l1:l2,m,n-3)))
        else
          df=0.
        endif
      endif
!
    endsubroutine der6_other
!***********************************************************************
    real function der5_single(f,j,dc1)
!
!  computes 5th order derivative of function given by f at position j
!
!   3-oct-12/MR: coded
!
      real, dimension(:),  intent(in) :: f, dc1
      integer           ,  intent(in) :: j
!
      real :: fac
!
      if (size(f)/=1) then
        fac=dc1(j)**5
        der5_single=fac*(+  2.5*(f(j+1)-f(j-1)) &
                         -  2.0*(f(j+2)-f(j-2)) &
                         +  0.5*(f(j+3)-f(j-3)))
      else
        der5_single=0.
      endif
!
    endfunction der5_single
!***********************************************************************
    subroutine derij_main(f,k,df,i,j)
!
!  calculate 2nd derivative with respect to two different directions
!  input: scalar, output: scalar
!  accurate to 6th order, explicit, periodic
!
!   8-sep-01/axel: coded
!  25-jun-04/tobi+wolf: adapted for non-equidistant grids
!  14-nov-06/wolf: implemented bidiagonal scheme
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df,fac
      integer :: i,j,k
!
      intent(in) :: f,k,i,j
      intent(out) :: df
!
!
! crash if this is called with i=j
!
!      if (i.eq.j) call fatal_error('derij_main','i=j, no derivative calculated')
!
!debug      if (loptimise_ders) der_call_count(k,icount_derij,i,j) = & !DERCOUNT
!debug                          der_call_count(k,icount_derij,i,j) + 1 !DERCOUNT
!
      if (lbidiagonal_derij) then
        !
        ! Use bidiagonal mixed-derivative operator, i.e.
        ! employ only the three neighbouring points on each of the four
        ! half-diagonals. This gives 6th-order mixed derivatives as the
        ! version below, but involves just 12 points instead of 36.
        !
        if ((i==1.and.j==2).or.(i==2.and.j==1)) then
          if (nxgrid/=1.and.nygrid/=1) then
            fac=(1./720.)*dx_1(l1:l2)*dy_1(m)
            df=fac*( &
                        270.*( f(l1+1:l2+1,m+1,n,k)-f(l1-1:l2-1,m+1,n,k)  &
                              +f(l1-1:l2-1,m-1,n,k)-f(l1+1:l2+1,m-1,n,k)) &
                       - 27.*( f(l1+2:l2+2,m+2,n,k)-f(l1-2:l2-2,m+2,n,k)  &
                              +f(l1-2:l2-2,m-2,n,k)-f(l1+2:l2+2,m-2,n,k)) &
                       +  2.*( f(l1+3:l2+3,m+3,n,k)-f(l1-3:l2-3,m+3,n,k)  &
                              +f(l1-3:l2-3,m-3,n,k)-f(l1+3:l2+3,m-3,n,k)) &
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or y-direction'
          endif
        elseif ((i==2.and.j==3).or.(i==3.and.j==2)) then
          if (nygrid/=1.and.nzgrid/=1) then
            fac=(1./720.)*dy_1(m)*dz_1(n)
            df=fac*( &
                        270.*( f(l1:l2,m+1,n+1,k)-f(l1:l2,m+1,n-1,k)  &
                              +f(l1:l2,m-1,n-1,k)-f(l1:l2,m-1,n+1,k)) &
                       - 27.*( f(l1:l2,m+2,n+2,k)-f(l1:l2,m+2,n-2,k)  &
                              +f(l1:l2,m-2,n-2,k)-f(l1:l2,m-2,n+2,k)) &
                       +  2.*( f(l1:l2,m+3,n+3,k)-f(l1:l2,m+3,n-3,k)  &
                              +f(l1:l2,m-3,n-3,k)-f(l1:l2,m-3,n+3,k)) &
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in y- or z-direction'
          endif
        elseif ((i==3.and.j==1).or.(i==1.and.j==3)) then
          if (nzgrid/=1.and.nxgrid/=1) then
            fac=(1./720.)*dz_1(n)*dx_1(l1:l2)
            df=fac*( &
                        270.*( f(l1+1:l2+1,m,n+1,k)-f(l1-1:l2-1,m,n+1,k)  &
                              +f(l1-1:l2-1,m,n-1,k)-f(l1+1:l2+1,m,n-1,k)) &
                       - 27.*( f(l1+2:l2+2,m,n+2,k)-f(l1-2:l2-2,m,n+2,k)  &
                              +f(l1-2:l2-2,m,n-2,k)-f(l1+2:l2+2,m,n-2,k)) &
                       +  2.*( f(l1+3:l2+3,m,n+3,k)-f(l1-3:l2-3,m,n+3,k)  &
                              +f(l1-3:l2-3,m,n-3,k)-f(l1+3:l2+3,m,n-3,k)) &
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or z-direction'
          endif
        endif
!
      else                      ! not using bidiagonal mixed derivatives
        !
        ! This is the old, straight-forward scheme
        !
        if ((i==1.and.j==2).or.(i==2.and.j==1)) then
          if (nxgrid/=1.and.nygrid/=1) then
            fac=(1./60.**2)*dx_1(l1:l2)*dy_1(m)
            df=fac*( &
              45.*((45.*(f(l1+1:l2+1,m+1,n,k)-f(l1-1:l2-1,m+1,n,k))  &
                    -9.*(f(l1+2:l2+2,m+1,n,k)-f(l1-2:l2-2,m+1,n,k))  &
                       +(f(l1+3:l2+3,m+1,n,k)-f(l1-3:l2-3,m+1,n,k))) &
                  -(45.*(f(l1+1:l2+1,m-1,n,k)-f(l1-1:l2-1,m-1,n,k))  &
                    -9.*(f(l1+2:l2+2,m-1,n,k)-f(l1-2:l2-2,m-1,n,k))  &
                       +(f(l1+3:l2+3,m-1,n,k)-f(l1-3:l2-3,m-1,n,k))))&
              -9.*((45.*(f(l1+1:l2+1,m+2,n,k)-f(l1-1:l2-1,m+2,n,k))  &
                    -9.*(f(l1+2:l2+2,m+2,n,k)-f(l1-2:l2-2,m+2,n,k))  &
                       +(f(l1+3:l2+3,m+2,n,k)-f(l1-3:l2-3,m+2,n,k))) &
                  -(45.*(f(l1+1:l2+1,m-2,n,k)-f(l1-1:l2-1,m-2,n,k))  &
                    -9.*(f(l1+2:l2+2,m-2,n,k)-f(l1-2:l2-2,m-2,n,k))  &
                       +(f(l1+3:l2+3,m-2,n,k)-f(l1-3:l2-3,m-2,n,k))))&
                 +((45.*(f(l1+1:l2+1,m+3,n,k)-f(l1-1:l2-1,m+3,n,k))  &
                    -9.*(f(l1+2:l2+2,m+3,n,k)-f(l1-2:l2-2,m+3,n,k))  &
                       +(f(l1+3:l2+3,m+3,n,k)-f(l1-3:l2-3,m+3,n,k))) &
                  -(45.*(f(l1+1:l2+1,m-3,n,k)-f(l1-1:l2-1,m-3,n,k))  &
                    -9.*(f(l1+2:l2+2,m-3,n,k)-f(l1-2:l2-2,m-3,n,k))  &
                       +(f(l1+3:l2+3,m-3,n,k)-f(l1-3:l2-3,m-3,n,k))))&
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or y-direction'
          endif
        elseif ((i==2.and.j==3).or.(i==3.and.j==2)) then
          if (nygrid/=1.and.nzgrid/=1) then
            fac=(1./60.**2)*dy_1(m)*dz_1(n)
            df=fac*( &
              45.*((45.*(f(l1:l2,m+1,n+1,k)-f(l1:l2,m-1,n+1,k))  &
                    -9.*(f(l1:l2,m+2,n+1,k)-f(l1:l2,m-2,n+1,k))  &
                       +(f(l1:l2,m+3,n+1,k)-f(l1:l2,m-3,n+1,k))) &
                  -(45.*(f(l1:l2,m+1,n-1,k)-f(l1:l2,m-1,n-1,k))  &
                    -9.*(f(l1:l2,m+2,n-1,k)-f(l1:l2,m-2,n-1,k))  &
                       +(f(l1:l2,m+3,n-1,k)-f(l1:l2,m-3,n-1,k))))&
              -9.*((45.*(f(l1:l2,m+1,n+2,k)-f(l1:l2,m-1,n+2,k))  &
                    -9.*(f(l1:l2,m+2,n+2,k)-f(l1:l2,m-2,n+2,k))  &
                       +(f(l1:l2,m+3,n+2,k)-f(l1:l2,m-3,n+2,k))) &
                  -(45.*(f(l1:l2,m+1,n-2,k)-f(l1:l2,m-1,n-2,k))  &
                    -9.*(f(l1:l2,m+2,n-2,k)-f(l1:l2,m-2,n-2,k))  &
                       +(f(l1:l2,m+3,n-2,k)-f(l1:l2,m-3,n-2,k))))&
                 +((45.*(f(l1:l2,m+1,n+3,k)-f(l1:l2,m-1,n+3,k))  &
                    -9.*(f(l1:l2,m+2,n+3,k)-f(l1:l2,m-2,n+3,k))  &
                       +(f(l1:l2,m+3,n+3,k)-f(l1:l2,m-3,n+3,k))) &
                  -(45.*(f(l1:l2,m+1,n-3,k)-f(l1:l2,m-1,n-3,k))  &
                    -9.*(f(l1:l2,m+2,n-3,k)-f(l1:l2,m-2,n-3,k))  &
                       +(f(l1:l2,m+3,n-3,k)-f(l1:l2,m-3,n-3,k))))&
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in y- or z-direction'
          endif
        elseif ((i==3.and.j==1).or.(i==1.and.j==3)) then
          if (nzgrid/=1.and.nxgrid/=1) then
            fac=(1./60.**2)*dz_1(n)*dx_1(l1:l2)
            df=fac*( &
              45.*((45.*(f(l1+1:l2+1,m,n+1,k)-f(l1-1:l2-1,m,n+1,k))  &
                    -9.*(f(l1+2:l2+2,m,n+1,k)-f(l1-2:l2-2,m,n+1,k))  &
                       +(f(l1+3:l2+3,m,n+1,k)-f(l1-3:l2-3,m,n+1,k))) &
                  -(45.*(f(l1+1:l2+1,m,n-1,k)-f(l1-1:l2-1,m,n-1,k))  &
                    -9.*(f(l1+2:l2+2,m,n-1,k)-f(l1-2:l2-2,m,n-1,k))  &
                       +(f(l1+3:l2+3,m,n-1,k)-f(l1-3:l2-3,m,n-1,k))))&
              -9.*((45.*(f(l1+1:l2+1,m,n+2,k)-f(l1-1:l2-1,m,n+2,k))  &
                    -9.*(f(l1+2:l2+2,m,n+2,k)-f(l1-2:l2-2,m,n+2,k))  &
                       +(f(l1+3:l2+3,m,n+2,k)-f(l1-3:l2-3,m,n+2,k))) &
                  -(45.*(f(l1+1:l2+1,m,n-2,k)-f(l1-1:l2-1,m,n-2,k))  &
                    -9.*(f(l1+2:l2+2,m,n-2,k)-f(l1-2:l2-2,m,n-2,k))  &
                       +(f(l1+3:l2+3,m,n-2,k)-f(l1-3:l2-3,m,n-2,k))))&
                 +((45.*(f(l1+1:l2+1,m,n+3,k)-f(l1-1:l2-1,m,n+3,k))  &
                    -9.*(f(l1+2:l2+2,m,n+3,k)-f(l1-2:l2-2,m,n+3,k))  &
                       +(f(l1+3:l2+3,m,n+3,k)-f(l1-3:l2-3,m,n+3,k))) &
                  -(45.*(f(l1+1:l2+1,m,n-3,k)-f(l1-1:l2-1,m,n-3,k))  &
                    -9.*(f(l1+2:l2+2,m,n-3,k)-f(l1-2:l2-2,m,n-3,k))  &
                       +(f(l1+3:l2+3,m,n-3,k)-f(l1-3:l2-3,m,n-3,k))))&
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or z-direction'
          endif
        endif
!
      endif                     ! bidiagonal derij
!
!  Spherical polars. The comments about "minus extra terms" refer to the
!  presence of extra terms that are being evaluated later in gij_etc.
!
      if (lspherical_coords) then
        if ((i==1.and.j==2)) df=df*r1_mn
        if ((i==2.and.j==1)) df=df*r1_mn !(minus extra terms)
        if ((i==1.and.j==3)) df=df*r1_mn*sin1th(m)
        if ((i==3.and.j==1)) df=df*r1_mn*sin1th(m) !(minus extra terms)
        if ((i==2.and.j==3)) df=df*r2_mn*sin1th(m)
        if ((i==3.and.j==2)) df=df*r2_mn*sin1th(m) !(minus extra terms)
      endif
!
      if (lcylindrical_coords) then
        if ((i==1.and.j==2)) df=df*rcyl_mn1
        if ((i==2.and.j==1)) df=df*rcyl_mn1
        if ((i==1.and.j==3)) df=df
        if ((i==3.and.j==1)) df=df
        if ((i==2.and.j==3)) df=df*rcyl_mn1
        if ((i==3.and.j==2)) df=df*rcyl_mn1
      endif
!
    endsubroutine derij_main
!***********************************************************************
    subroutine derij_other(f,df,i,j)
!
!  calculate 2nd derivative with respect to two different directions
!  input: scalar, output: scalar
!  accurate to 6th order, explicit, periodic
!   8-sep-01/axel: coded
!  25-jun-04/tobi+wolf: adapted for non-equidistant grids
!  14-nov-06/wolf: implemented bidiagonal scheme
!
      real, dimension (mx,my,mz) :: f
      real, dimension (nx) :: df,fac
      integer :: i,j
!
      intent(in)  :: f,i,j
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_derij,i,j) = & !DERCOUNT
!debug                          der_call_count(k,icount_derij,i,j) + 1 !DERCOUNT
!
      if (lbidiagonal_derij) then
        !
        ! Use bidiagonal mixed-derivative operator, i.e.
        ! employ only the three neighbouring points on each of the four
        ! half-diagonals. This gives 6th-order mixed derivatives as the
        ! version below, but involves just 12 points instead of 36.
        !
        if ((i==1.and.j==2).or.(i==2.and.j==1)) then
          if (nxgrid/=1.and.nygrid/=1) then
            fac=(1./720.)*dx_1(l1:l2)*dy_1(m)
            df=fac*( &
                        270.*( f(l1+1:l2+1,m+1,n)-f(l1-1:l2-1,m+1,n)  &
                              +f(l1-1:l2-1,m-1,n)-f(l1+1:l2+1,m-1,n)) &
                       - 27.*( f(l1+2:l2+2,m+2,n)-f(l1-2:l2-2,m+2,n)  &
                              +f(l1-2:l2-2,m-2,n)-f(l1+2:l2+2,m-2,n)) &
                       +  2.*( f(l1+3:l2+3,m+3,n)-f(l1-3:l2-3,m+3,n)  &
                              +f(l1-3:l2-3,m-3,n)-f(l1+3:l2+3,m-3,n)) &
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or y-direction'
          endif
        elseif ((i==2.and.j==3).or.(i==3.and.j==2)) then
          if (nygrid/=1.and.nzgrid/=1) then
            fac=(1./720.)*dy_1(m)*dz_1(n)
            df=fac*( &
                        270.*( f(l1:l2,m+1,n+1)-f(l1:l2,m+1,n-1)  &
                              +f(l1:l2,m-1,n-1)-f(l1:l2,m-1,n+1)) &
                       - 27.*( f(l1:l2,m+2,n+2)-f(l1:l2,m+2,n-2)  &
                              +f(l1:l2,m-2,n-2)-f(l1:l2,m-2,n+2)) &
                       +  2.*( f(l1:l2,m+3,n+3)-f(l1:l2,m+3,n-3)  &
                              +f(l1:l2,m-3,n-3)-f(l1:l2,m-3,n+3)) &
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in y- or z-direction'
          endif
        elseif ((i==3.and.j==1).or.(i==1.and.j==3)) then
          if (nzgrid/=1.and.nxgrid/=1) then
            fac=(1./720.)*dz_1(n)*dx_1(l1:l2)
            df=fac*( &
                        270.*( f(l1+1:l2+1,m,n+1)-f(l1-1:l2-1,m,n+1)  &
                              +f(l1-1:l2-1,m,n-1)-f(l1+1:l2+1,m,n-1)) &
                       - 27.*( f(l1+2:l2+2,m,n+2)-f(l1-2:l2-2,m,n+2)  &
                              +f(l1-2:l2-2,m,n-2)-f(l1+2:l2+2,m,n-2)) &
                       +  2.*( f(l1+3:l2+3,m,n+3)-f(l1-3:l2-3,m,n+3)  &
                              +f(l1-3:l2-3,m,n-3)-f(l1+3:l2+3,m,n-3)) &
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or z-direction'
          endif
        endif
!
      else                      ! not using bidiagonal mixed derivatives
        !
        ! This is the old, straight-forward scheme
        !
        if ((i==1.and.j==2).or.(i==2.and.j==1)) then
          if (nxgrid/=1.and.nygrid/=1) then
            fac=(1./60.**2)*dx_1(l1:l2)*dy_1(m)
            df=fac*( &
              45.*((45.*(f(l1+1:l2+1,m+1,n)-f(l1-1:l2-1,m+1,n))  &
                    -9.*(f(l1+2:l2+2,m+1,n)-f(l1-2:l2-2,m+1,n))  &
                       +(f(l1+3:l2+3,m+1,n)-f(l1-3:l2-3,m+1,n))) &
                  -(45.*(f(l1+1:l2+1,m-1,n)-f(l1-1:l2-1,m-1,n))  &
                    -9.*(f(l1+2:l2+2,m-1,n)-f(l1-2:l2-2,m-1,n))  &
                       +(f(l1+3:l2+3,m-1,n)-f(l1-3:l2-3,m-1,n))))&
              -9.*((45.*(f(l1+1:l2+1,m+2,n)-f(l1-1:l2-1,m+2,n))  &
                    -9.*(f(l1+2:l2+2,m+2,n)-f(l1-2:l2-2,m+2,n))  &
                       +(f(l1+3:l2+3,m+2,n)-f(l1-3:l2-3,m+2,n))) &
                  -(45.*(f(l1+1:l2+1,m-2,n)-f(l1-1:l2-1,m-2,n))  &
                    -9.*(f(l1+2:l2+2,m-2,n)-f(l1-2:l2-2,m-2,n))  &
                       +(f(l1+3:l2+3,m-2,n)-f(l1-3:l2-3,m-2,n))))&
                 +((45.*(f(l1+1:l2+1,m+3,n)-f(l1-1:l2-1,m+3,n))  &
                    -9.*(f(l1+2:l2+2,m+3,n)-f(l1-2:l2-2,m+3,n))  &
                       +(f(l1+3:l2+3,m+3,n)-f(l1-3:l2-3,m+3,n))) &
                  -(45.*(f(l1+1:l2+1,m-3,n)-f(l1-1:l2-1,m-3,n))  &
                    -9.*(f(l1+2:l2+2,m-3,n)-f(l1-2:l2-2,m-3,n))  &
                       +(f(l1+3:l2+3,m-3,n)-f(l1-3:l2-3,m-3,n))))&
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or y-direction'
          endif
        elseif ((i==2.and.j==3).or.(i==3.and.j==2)) then
          if (nygrid/=1.and.nzgrid/=1) then
            fac=(1./60.**2)*dy_1(m)*dz_1(n)
            df=fac*( &
              45.*((45.*(f(l1:l2,m+1,n+1)-f(l1:l2,m-1,n+1))  &
                    -9.*(f(l1:l2,m+2,n+1)-f(l1:l2,m-2,n+1))  &
                       +(f(l1:l2,m+3,n+1)-f(l1:l2,m-3,n+1))) &
                  -(45.*(f(l1:l2,m+1,n-1)-f(l1:l2,m-1,n-1))  &
                    -9.*(f(l1:l2,m+2,n-1)-f(l1:l2,m-2,n-1))  &
                       +(f(l1:l2,m+3,n-1)-f(l1:l2,m-3,n-1))))&
              -9.*((45.*(f(l1:l2,m+1,n+2)-f(l1:l2,m-1,n+2))  &
                    -9.*(f(l1:l2,m+2,n+2)-f(l1:l2,m-2,n+2))  &
                       +(f(l1:l2,m+3,n+2)-f(l1:l2,m-3,n+2))) &
                  -(45.*(f(l1:l2,m+1,n-2)-f(l1:l2,m-1,n-2))  &
                    -9.*(f(l1:l2,m+2,n-2)-f(l1:l2,m-2,n-2))  &
                       +(f(l1:l2,m+3,n-2)-f(l1:l2,m-3,n-2))))&
                 +((45.*(f(l1:l2,m+1,n+3)-f(l1:l2,m-1,n+3))  &
                    -9.*(f(l1:l2,m+2,n+3)-f(l1:l2,m-2,n+3))  &
                       +(f(l1:l2,m+3,n+3)-f(l1:l2,m-3,n+3))) &
                  -(45.*(f(l1:l2,m+1,n-3)-f(l1:l2,m-1,n-3))  &
                    -9.*(f(l1:l2,m+2,n-3)-f(l1:l2,m-2,n-3))  &
                       +(f(l1:l2,m+3,n-3)-f(l1:l2,m-3,n-3))))&
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in y- or z-direction'
          endif
        elseif ((i==3.and.j==1).or.(i==1.and.j==3)) then
          if (nzgrid/=1.and.nxgrid/=1) then
            fac=(1./60.**2)*dz_1(n)*dx_1(l1:l2)
            df=fac*( &
              45.*((45.*(f(l1+1:l2+1,m,n+1)-f(l1-1:l2-1,m,n+1))  &
                    -9.*(f(l1+2:l2+2,m,n+1)-f(l1-2:l2-2,m,n+1))  &
                       +(f(l1+3:l2+3,m,n+1)-f(l1-3:l2-3,m,n+1))) &
                  -(45.*(f(l1+1:l2+1,m,n-1)-f(l1-1:l2-1,m,n-1))  &
                    -9.*(f(l1+2:l2+2,m,n-1)-f(l1-2:l2-2,m,n-1))  &
                       +(f(l1+3:l2+3,m,n-1)-f(l1-3:l2-3,m,n-1))))&
              -9.*((45.*(f(l1+1:l2+1,m,n+2)-f(l1-1:l2-1,m,n+2))  &
                    -9.*(f(l1+2:l2+2,m,n+2)-f(l1-2:l2-2,m,n+2))  &
                       +(f(l1+3:l2+3,m,n+2)-f(l1-3:l2-3,m,n+2))) &
                  -(45.*(f(l1+1:l2+1,m,n-2)-f(l1-1:l2-1,m,n-2))  &
                    -9.*(f(l1+2:l2+2,m,n-2)-f(l1-2:l2-2,m,n-2))  &
                       +(f(l1+3:l2+3,m,n-2)-f(l1-3:l2-3,m,n-2))))&
                 +((45.*(f(l1+1:l2+1,m,n+3)-f(l1-1:l2-1,m,n+3))  &
                    -9.*(f(l1+2:l2+2,m,n+3)-f(l1-2:l2-2,m,n+3))  &
                       +(f(l1+3:l2+3,m,n+3)-f(l1-3:l2-3,m,n+3))) &
                  -(45.*(f(l1+1:l2+1,m,n-3)-f(l1-1:l2-1,m,n-3))  &
                    -9.*(f(l1+2:l2+2,m,n-3)-f(l1-2:l2-2,m,n-3))  &
                       +(f(l1+3:l2+3,m,n-3)-f(l1-3:l2-3,m,n-3))))&
                   )
          else
            df=0.
            if (ip<=5) print*, 'derij: Degenerate case in x- or z-direction'
          endif
        endif
!
      endif                     ! bidiagonal derij
!
!  Spherical polars. The comments about "minus extra terms" refer to the
!  presence of extra terms that are being evaluated later in gij_etc.
!
      if (lspherical_coords) then
        if ((i==1.and.j==2)) df=df*r1_mn
        if ((i==2.and.j==1)) df=df*r1_mn !(minus extra terms)
        if ((i==1.and.j==3)) df=df*r1_mn*sin1th(m)
        if ((i==3.and.j==1)) df=df*r1_mn*sin1th(m) !(minus extra terms)
        if ((i==2.and.j==3)) df=df*r2_mn*sin1th(m)
        if ((i==3.and.j==2)) df=df*r2_mn*sin1th(m) !(minus extra terms)
      endif
!
      if (lcylindrical_coords) then
        if ((i==1.and.j==2)) df=df*rcyl_mn1
        if ((i==2.and.j==1)) df=df*rcyl_mn1
        if ((i==1.and.j==3)) df=df
        if ((i==3.and.j==1)) df=df
        if ((i==2.and.j==3)) df=df*rcyl_mn1
        if ((i==3.and.j==2)) df=df*rcyl_mn1
      endif
!
    endsubroutine derij_other
!***********************************************************************
    subroutine der5i1j(f,k,df,i,j)
!
!  Calculate 6th derivative with respect to two different directions.
!
!  05-dec-06/anders: adapted from derij
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: df,fac
      integer :: i,j,k
!
      intent(in) :: f,k,i,j
      intent(out) :: df
!debug      if (loptimise_ders) der_call_count(k,icount_derij,i,j) = & !DERCOUNT
!debug                          der_call_count(k,icount_derij,i,j) + 1 !DERCOUNT
!
!
      if (lspherical_coords.or.lcylindrical_coords) &
          call fatal_error('der5i1j','NOT IMPLEMENTED for non-cartesian coordinates')
!
      df=0.0
      if ((i==1.and.j==1)) then
        if (nxgrid/=1) then
          call der6(f,k,df,j)
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in x-direction'
        endif
      elseif ((i==2.and.j==2)) then
        if (nygrid/=1) then
          call der6(f,k,df,j)
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in y-direction'
        endif
      elseif ((i==3.and.j==3)) then
        if (nzgrid/=1) then
          call der6(f,k,df,j)
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in z-direction'
        endif
      elseif ((i==1.and.j==2)) then
        if (nxgrid/=1.and.nygrid/=1) then
          fac=dx_1(l1:l2)**5*1/60.0*dy_1(m)
          df=fac*( &
            2.5*((45.*(f(l1+1:l2+1,m+1,n,k)-f(l1+1:l2+1,m-1,n,k))  &
                  -9.*(f(l1+1:l2+1,m+2,n,k)-f(l1+1:l2+1,m-2,n,k))  &
                     +(f(l1+1:l2+1,m+3,n,k)-f(l1+1:l2+1,m-3,n,k))) &
                -(45.*(f(l1-1:l2-1,m+1,n,k)-f(l1-1:l2-1,m-1,n,k))  &
                  -9.*(f(l1-1:l2-1,m+2,n,k)-f(l1-1:l2-1,m-2,n,k))  &
                     +(f(l1-1:l2-1,m+3,n,k)-f(l1-1:l2-1,m-3,n,k))))&
           -2.0*((45.*(f(l1+2:l2+2,m+1,n,k)-f(l1+2:l2+2,m-1,n,k))  &
                  -9.*(f(l1+2:l2+2,m+2,n,k)-f(l1+2:l2+2,m-2,n,k))  &
                     +(f(l1+2:l2+2,m+3,n,k)-f(l1+2:l2+2,m-3,n,k))) &
                -(45.*(f(l1-2:l2-2,m+1,n,k)-f(l1-2:l2-2,m-1,n,k))  &
                  -9.*(f(l1-2:l2-2,m+2,n,k)-f(l1-2:l2-2,m-2,n,k))  &
                     +(f(l1-2:l2-2,m+3,n,k)-f(l1-2:l2-2,m-3,n,k))))&
           +0.5*((45.*(f(l1+3:l2+3,m+1,n,k)-f(l1+3:l2+3,m-1,n,k))  &
                  -9.*(f(l1+3:l2+3,m+2,n,k)-f(l1+3:l2+3,m-2,n,k))  &
                     +(f(l1+3:l2+3,m+3,n,k)-f(l1+3:l2+3,m-3,n,k))) &
                -(45.*(f(l1-3:l2-3,m+1,n,k)-f(l1-3:l2-3,m-1,n,k))  &
                  -9.*(f(l1-3:l2-3,m+2,n,k)-f(l1-3:l2-3,m-2,n,k))  &
                     +(f(l1-3:l2-3,m+3,n,k)-f(l1-3:l2-3,m-3,n,k))))&
                 )
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in x- or y-direction'
        endif
      elseif ((i==2.and.j==1)) then
        if (nygrid/=1.and.nxgrid/=1) then
          fac=dy_1(m)**5*1/60.0*dx_1(l1:l2)
          df=fac*( &
            2.5*((45.*(f(l1+1:l2+1,m+1,n,k)-f(l1-1:l2-1,m+1,n,k))  &
                  -9.*(f(l1+2:l2+2,m+1,n,k)-f(l1-2:l2-2,m+1,n,k))  &
                     +(f(l1+3:l2+3,m+1,n,k)-f(l1-3:l2-3,m+1,n,k))) &
                -(45.*(f(l1+1:l2+1,m-1,n,k)-f(l1-1:l2-1,m-1,n,k))  &
                  -9.*(f(l1+2:l2+2,m-1,n,k)-f(l1-2:l2-2,m-1,n,k))  &
                     +(f(l1+3:l2+3,m-1,n,k)-f(l1-3:l2-3,m-1,n,k))))&
           -2.0*((45.*(f(l1+1:l2+1,m+2,n,k)-f(l1-1:l2-1,m+2,n,k))  &
                  -9.*(f(l1+2:l2+2,m+2,n,k)-f(l1-2:l2-2,m+2,n,k))  &
                     +(f(l1+3:l2+3,m+2,n,k)-f(l1-3:l2-3,m+2,n,k))) &
                -(45.*(f(l1+1:l2+1,m-2,n,k)-f(l1-1:l2-1,m-2,n,k))  &
                  -9.*(f(l1+2:l2+2,m-2,n,k)-f(l1-2:l2-2,m-2,n,k))  &
                     +(f(l1+3:l2+3,m-2,n,k)-f(l1-3:l2-3,m-2,n,k))))&
           +0.5*((45.*(f(l1+1:l2+1,m+3,n,k)-f(l1-1:l2-1,m+3,n,k))  &
                  -9.*(f(l1+2:l2+2,m+3,n,k)-f(l1-2:l2-2,m+3,n,k))  &
                     +(f(l1+3:l2+3,m+3,n,k)-f(l1-3:l2-3,m+3,n,k))) &
                -(45.*(f(l1+1:l2+1,m-3,n,k)-f(l1-1:l2-1,m-3,n,k))  &
                  -9.*(f(l1+2:l2+2,m-3,n,k)-f(l1-2:l2-2,m-3,n,k))  &
                     +(f(l1+3:l2+3,m-3,n,k)-f(l1-3:l2-3,m-3,n,k))))&
                 )
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in y- or x-direction'
        endif
      elseif ((i==1.and.j==3)) then
        if (nxgrid/=1.and.nzgrid/=1) then
          fac=dx_1(l1:l2)**5*1/60.0*dz_1(n)
          df=fac*( &
            2.5*((45.*(f(l1+1:l2+1,m,n+1,k)-f(l1+1:l2+1,m,n-1,k))  &
                  -9.*(f(l1+1:l2+1,m,n+2,k)-f(l1+1:l2+1,m,n-2,k))  &
                     +(f(l1+1:l2+1,m,n+3,k)-f(l1+1:l2+1,m,n-3,k))) &
                -(45.*(f(l1-1:l2-1,m,n+1,k)-f(l1-1:l2-1,m,n-1,k))  &
                  -9.*(f(l1-1:l2-1,m,n+2,k)-f(l1-1:l2-1,m,n-2,k))  &
                     +(f(l1-1:l2-1,m,n+3,k)-f(l1-1:l2-1,m,n-3,k))))&
           -2.0*((45.*(f(l1+2:l2+2,m,n+1,k)-f(l1+2:l2+2,m,n-1,k))  &
                  -9.*(f(l1+2:l2+2,m,n+2,k)-f(l1+2:l2+2,m,n-2,k))  &
                     +(f(l1+2:l2+2,m,n+3,k)-f(l1+2:l2+2,m,n-3,k))) &
                -(45.*(f(l1-2:l2-2,m,n+1,k)-f(l1-2:l2-2,m,n-1,k))  &
                  -9.*(f(l1-2:l2-2,m,n+2,k)-f(l1-2:l2-2,m,n-2,k))  &
                     +(f(l1-2:l2-2,m,n+3,k)-f(l1-2:l2-2,m,n-3,k))))&
           +0.5*((45.*(f(l1+3:l2+3,m,n+1,k)-f(l1+3:l2+3,m,n-1,k))  &
                  -9.*(f(l1+3:l2+3,m,n+2,k)-f(l1+3:l2+3,m,n-2,k))  &
                     +(f(l1+3:l2+3,m,n+3,k)-f(l1+3:l2+3,m,n-3,k))) &
                -(45.*(f(l1-3:l2-3,m,n+1,k)-f(l1-3:l2-3,m,n-1,k))  &
                  -9.*(f(l1-3:l2-3,m,n+2,k)-f(l1-3:l2-3,m,n-2,k))  &
                     +(f(l1-3:l2-3,m,n+3,k)-f(l1-3:l2-3,m,n-3,k))))&
                 )
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in x- or z-direction'
        endif
      elseif ((i==3.and.j==1)) then
        if (nzgrid/=1.and.nygrid/=1) then
          fac=dz_1(n)**5*1/60.0*dy_1(m)
          df=fac*( &
            2.5*((45.*(f(l1+1:l2+1,m,n+1,k)-f(l1-1:l2-1,m,n+1,k))  &
                  -9.*(f(l1+2:l2+2,m,n+1,k)-f(l1-2:l2-2,m,n+1,k))  &
                     +(f(l1+3:l2+3,m,n+1,k)-f(l1-3:l2-3,m,n+1,k))) &
                -(45.*(f(l1+1:l2+1,m,n-1,k)-f(l1-1:l2-1,m,n-1,k))  &
                  -9.*(f(l1+2:l2+2,m,n-1,k)-f(l1-2:l2-2,m,n-1,k))  &
                     +(f(l1+3:l2+3,m,n-1,k)-f(l1-3:l2-3,m,n-1,k))))&
           -2.0*((45.*(f(l1+1:l2+1,m,n+2,k)-f(l1-1:l2-1,m,n+2,k))  &
                  -9.*(f(l1+2:l2+2,m,n+2,k)-f(l1-2:l2-2,m,n+2,k))  &
                     +(f(l1+3:l2+3,m,n+2,k)-f(l1-3:l2-3,m,n+2,k))) &
                -(45.*(f(l1+1:l2+1,m,n-2,k)-f(l1-1:l2-1,m,n-2,k))  &
                  -9.*(f(l1+2:l2+2,m,n-2,k)-f(l1-2:l2-2,m,n-2,k))  &
                     +(f(l1+3:l2+3,m,n-2,k)-f(l1-3:l2-3,m,n-2,k))))&
           +0.5*((45.*(f(l1+1:l2+1,m,n+3,k)-f(l1-1:l2-1,m,n+3,k))  &
                  -9.*(f(l1+2:l2+2,m,n+3,k)-f(l1-2:l2-2,m,n+3,k))  &
                     +(f(l1+3:l2+3,m,n+3,k)-f(l1-3:l2-3,m,n+3,k))) &
                -(45.*(f(l1+1:l2+1,m,n-3,k)-f(l1-1:l2-1,m,n-3,k))  &
                  -9.*(f(l1+2:l2+2,m,n-3,k)-f(l1-2:l2-2,m,n-3,k))  &
                     +(f(l1+3:l2+3,m,n-3,k)-f(l1-3:l2-3,m,n-3,k))))&
                 )
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in z- or x-direction'
        endif
      elseif ((i==2.and.j==3)) then
        if (nygrid/=1.and.nzgrid/=1) then
          fac=dy_1(m)**5*1/60.0*dz_1(n)
          df=fac*( &
            2.5*((45.*(f(l1:l2,m+1,n+1,k)-f(l1:l2,m+1,n-1,k))  &
                  -9.*(f(l1:l2,m+1,n+2,k)-f(l1:l2,m+1,n-2,k))  &
                     +(f(l1:l2,m+1,n+3,k)-f(l1:l2,m+1,n-3,k))) &
                -(45.*(f(l1:l2,m-1,n+1,k)-f(l1:l2,m-1,n-1,k))  &
                  -9.*(f(l1:l2,m-1,n+2,k)-f(l1:l2,m-1,n-2,k))  &
                     +(f(l1:l2,m-1,n+3,k)-f(l1:l2,m-1,n-3,k))))&
           -2.0*((45.*(f(l1:l2,m+2,n+1,k)-f(l1:l2,m+2,n-1,k))  &
                  -9.*(f(l1:l2,m+2,n+2,k)-f(l1:l2,m+2,n-2,k))  &
                     +(f(l1:l2,m+2,n+3,k)-f(l1:l2,m+2,n-3,k))) &
                -(45.*(f(l1:l2,m-2,n+1,k)-f(l1:l2,m-2,n-1,k))  &
                  -9.*(f(l1:l2,m-2,n+2,k)-f(l1:l2,m-2,n-2,k))  &
                     +(f(l1:l2,m-2,n+3,k)-f(l1:l2,m-2,n-3,k))))&
           +0.5*((45.*(f(l1:l2,m+3,n+1,k)-f(l1:l2,m+3,n-1,k))  &
                  -9.*(f(l1:l2,m+3,n+2,k)-f(l1:l2,m+3,n-2,k))  &
                     +(f(l1:l2,m+3,n+3,k)-f(l1:l2,m+3,n-3,k))) &
                -(45.*(f(l1:l2,m-3,n+1,k)-f(l1:l2,m-3,n-1,k))  &
                  -9.*(f(l1:l2,m-3,n+2,k)-f(l1:l2,m-3,n-2,k))  &
                     +(f(l1:l2,m-3,n+3,k)-f(l1:l2,m-3,n-3,k))))&
                 )
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in y- or z-direction'
        endif
      elseif ((i==3.and.j==2)) then
        if (nzgrid/=1.and.nygrid/=1) then
          fac=dz_1(n)**5*1/60.0*dy_1(m)
          df=fac*( &
            2.5*((45.*(f(l1:l2,m+1,n+1,k)-f(l1:l2,m-1,n+1,k))  &
                  -9.*(f(l1:l2,m+2,n+1,k)-f(l1:l2,m-2,n+1,k))  &
                     +(f(l1:l2,m+3,n+1,k)-f(l1:l2,m-3,n+1,k))) &
                -(45.*(f(l1:l2,m+1,n-1,k)-f(l1:l2,m-1,n-1,k))  &
                  -9.*(f(l1:l2,m+2,n-1,k)-f(l1:l2,m-2,n-1,k))  &
                     +(f(l1:l2,m+3,n-1,k)-f(l1:l2,m-3,n-1,k))))&
           -2.0*((45.*(f(l1:l2,m+1,n+2,k)-f(l1:l2,m-1,n+2,k))  &
                  -9.*(f(l1:l2,m+2,n+2,k)-f(l1:l2,m-2,n+2,k))  &
                     +(f(l1:l2,m+3,n+2,k)-f(l1:l2,m-3,n+2,k))) &
                -(45.*(f(l1:l2,m+1,n-2,k)-f(l1:l2,m-1,n-2,k))  &
                  -9.*(f(l1:l2,m+2,n-2,k)-f(l1:l2,m-2,n-2,k))  &
                     +(f(l1:l2,m+3,n-2,k)-f(l1:l2,m-3,n-2,k))))&
           +0.5*((45.*(f(l1:l2,m+1,n+3,k)-f(l1:l2,m-1,n+3,k))  &
                  -9.*(f(l1:l2,m+2,n+3,k)-f(l1:l2,m-2,n+3,k))  &
                     +(f(l1:l2,m+3,n+3,k)-f(l1:l2,m-3,n+3,k))) &
                -(45.*(f(l1:l2,m+1,n-3,k)-f(l1:l2,m-1,n-3,k))  &
                  -9.*(f(l1:l2,m+2,n-3,k)-f(l1:l2,m-2,n-3,k))  &
                     +(f(l1:l2,m+3,n-3,k)-f(l1:l2,m-3,n-3,k))))&
                 )
        else
          df=0.
          if (ip<=5) print*, 'der5i1j: Degenerate case in z- or y-direction'
        endif
      else
        print*, 'der5i1j: no such value for i,j=', i, j
        call fatal_error('der5i1j','')
      endif
!
    endsubroutine der5i1j
!***********************************************************************
    subroutine der_upwind1st(f,uu,k,df,j)
!
!  First order upwind derivative of variable
!
!  Useful for advecting non-logarithmic variables
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx,3) :: uu
      real, dimension (nx) :: df
      integer :: j,k,l
!
      intent(in)  :: f,uu,k,j
      intent(out) :: df
!
!debug      if (loptimise_ders) der_call_count(k,icount_der_upwind1st,j,1) = & !DERCOUNT
!debug                          der_call_count(k,icount_der_upwind1st,j,1) + 1 !DERCOUNT
!
      if (lspherical_coords.or.lcylindrical_coords) &
          call fatal_error('der_upwind1st','NOT IMPLEMENTED for non-cartesian grid')
!
      if (j == 1) then
        if (nxgrid /= 1) then
          do l=1,nx
            if (uu(l,1) > 0.) then
              df(l) = (f(nghost+l  ,m,n,k) - f(nghost+l-1,m,n,k))*dx_1(nghost+l)
            else
              df(l) = (f(nghost+l+1,m,n,k) - f(nghost+l  ,m,n,k))*dx_1(nghost+l)
            endif
          enddo
        else
          df=0.
          if (ip<=5) print*, 'der_upwind1st: Degenerate case in x-direction'
        endif
      elseif (j == 2) then
        if (nygrid /= 1) then
          do l=1,nx
            if (uu(l,2) > 0.) then
              df(l) = (f(nghost+l,m  ,n,k) - f(nghost+l,m-1,n,k))*dy_1(m)
            else
              df(l) = (f(nghost+l,m+1,n,k) - f(nghost+l,m  ,n,k))*dy_1(m)
            endif
          enddo
        else
          df=0.
          if (ip<=5) print*, 'der_upwind1st: Degenerate case in y-direction'
        endif
      elseif (j == 3) then
        if (nzgrid /= 1) then
          do l=1,nx
            if (uu(l,3) > 0.) then
              df(l) = (f(nghost+l,m,n,k  ) - f(nghost+l,m,n-1,k))*dz_1(n)
            else
              df(l) = (f(nghost+l,m,n+1,k) - f(nghost+l,m,n,k  ))*dz_1(n)
            endif
          enddo
        else
          df=0.
          if (ip<=5) print*, 'der_upwind1st: Degenerate case in z-direction'
        endif
      endif
!
    endsubroutine der_upwind1st
!***********************************************************************
    subroutine der_onesided_4_slice_main(f,sgn,k,df,pos,j)
!
!   Calculate x/y/z-derivative on a yz/xz/xy-slice at gridpoint pos.
!   Uses a one-sided 4th order stencil.
!   sgn = +1 for forward difference, sgn = -1 for backwards difference.
!
!   Because of its original intended use in relation to solving
!   characteristic equations on boundaries (NSCBC), this sub should
!   return only PARTIAL derivatives, NOT COVARIANT. Applying the right
!   scaling factors and connection terms should instead be done when
!   solving the characteristic equations.
!
!   7-jul-08/arne: coded.
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (:,:) :: df
      real :: fac
      integer :: pos,k,sgn,j
!
      intent(in)  :: f,k,pos,sgn,j
      intent(out) :: df
!
      if (j==1) then
        if (nxgrid/=1) then
          fac=1./12.*dx_1(pos)
          df = fac*(-sgn*25*f(pos,m1:m2,n1:n2,k)&
                  +sgn*48*f(pos+sgn*1,m1:m2,n1:n2,k)&
                  -sgn*36*f(pos+sgn*2,m1:m2,n1:n2,k)&
                  +sgn*16*f(pos+sgn*3,m1:m2,n1:n2,k)&
                  -sgn*3 *f(pos+sgn*4,m1:m2,n1:n2,k))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in x-directder_onesided_4_sliceion'
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          fac=1./12.*dy_1(pos)
          df = fac*(-sgn*25*f(l1:l2,pos,n1:n2,k)&
                  +sgn*48*f(l1:l2,pos+sgn*1,n1:n2,k)&
                  -sgn*36*f(l1:l2,pos+sgn*2,n1:n2,k)&
                  +sgn*16*f(l1:l2,pos+sgn*3,n1:n2,k)&
                  -sgn*3 *f(l1:l2,pos+sgn*4,n1:n2,k))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in y-direction'
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          fac=1./12.*dz_1(pos)
          df = fac*(-sgn*25*f(l1:l2,m1:m2,pos,k)&
                  +sgn*48*f(l1:l2,m1:m2,pos+sgn*1,k)&
                  -sgn*36*f(l1:l2,m1:m2,pos+sgn*2,k)&
                  +sgn*16*f(l1:l2,m1:m2,pos+sgn*3,k)&
                  -sgn*3 *f(l1:l2,m1:m2,pos+sgn*4,k))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in z-direction'
        endif
      endif
    endsubroutine der_onesided_4_slice_main
!***********************************************************************
    subroutine der_onesided_4_slice_main_pt(f,sgn,k,df,lll,mmm,nnn,j)
!
!  made using der_onesided_4_slice_main. One sided derivative is calculated
!  at one point (lll,mmm,nnn)
!
!  15-oct-09/Natalia: coded.
!
      real, dimension (mx,my,mz,mfarray) :: f
      real  :: df
      real :: fac
      integer :: pos,lll,mmm,nnn,k,sgn,j
!
      intent(in)  :: f,k,lll,mmm,nnn,sgn,j
      intent(out) :: df
!
      if (j==1) then
       pos=lll
        if (nxgrid/=1) then
          fac=1./12.*dx_1(pos)
          df = fac*(-sgn*25*f(pos,mmm,nnn,k)&
                  +sgn*48*f(pos+sgn*1,mmm,nnn,k)&
                  -sgn*36*f(pos+sgn*2,mmm,nnn,k)&
                  +sgn*16*f(pos+sgn*3,mmm,nnn,k)&
                  -sgn*3 *f(pos+sgn*4,mmm,nnn,k))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in x-directder_onesided_4_sliceion'
        endif
      elseif (j==2) then
       pos=mmm
        if (nygrid/=1) then
          fac=1./12.*dy_1(pos)
          df = fac*(-sgn*25*f(lll,pos,nnn,k)&
                  +sgn*48*f(lll,pos+sgn*1,nnn,k)&
                  -sgn*36*f(lll,pos+sgn*2,nnn,k)&
                  +sgn*16*f(lll,pos+sgn*3,nnn,k)&
                  -sgn*3 *f(lll,pos+sgn*4,nnn,k))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in y-direction'
        endif
      elseif (j==3) then
       pos=nnn
        if (nzgrid/=1) then
          fac=1./12.*dz_1(pos)
          df = fac*(-sgn*25*f(lll,mmm,pos,k)&
                  +sgn*48*f(lll,mmm,pos+sgn*1,k)&
                  -sgn*36*f(lll,mmm,pos+sgn*2,k)&
                  +sgn*16*f(lll,mmm,pos+sgn*3,k)&
                  -sgn*3 *f(lll,mmm,pos+sgn*4,k))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in z-direction'
        endif
      endif
    endsubroutine der_onesided_4_slice_main_pt
!***********************************************************************
    subroutine der_onesided_4_slice_other(f,sgn,df,pos,j)
!
!   Calculate x/y/z-derivative on a yz/xz/xy-slice at gridpoint pos.
!   Uses a one-sided 4th order stencil.
!   sgn = +1 for forward difference, sgn = -1 for backwards difference.
!
!   Because of its original intended use in relation to solving
!   characteristic equations on boundaries (NSCBC), this sub should
!   return only PARTIAL derivatives, NOT COVARIANT. Applying the right
!   scaling factors and connection terms should instead be done when
!   solving the characteristic equations.
!
!   7-jul-08/arne: coded.
!
      real, dimension (mx,my,mz) :: f
      real, dimension (:,:) :: df
      real :: fac
      integer :: pos,sgn,j
!
      intent(in)  :: f,pos,sgn,j
      intent(out) :: df
!
      if (j==1) then
        if (nxgrid/=1) then
          fac=1./12.*dx_1(pos)
          df = fac*(-sgn*25*f(pos,m1:m2,n1:n2)&
                  +sgn*48*f(pos+sgn*1,m1:m2,n1:n2)&
                  -sgn*36*f(pos+sgn*2,m1:m2,n1:n2)&
                  +sgn*16*f(pos+sgn*3,m1:m2,n1:n2)&
                  -sgn*3 *f(pos+sgn*4,m1:m2,n1:n2))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in x-directder_onesided_4_sliceion'
        endif
      elseif (j==2) then
        if (nygrid/=1) then
          fac=1./12.*dy_1(pos)
          df = fac*(-sgn*25*(f(l1:l2,pos,n1:n2)-f(l1:l2,pos+sgn*1,n1:n2))&
                    +sgn*23*(f(l1:l2,pos+sgn*1,n1:n2)-f(l1:l2,pos+sgn*2,n1:n2))&
                    -sgn*13*(f(l1:l2,pos+sgn*2,n1:n2)-f(l1:l2,pos+sgn*3,n1:n2))&
                    +sgn*3*(f(l1:l2,pos+sgn*3,n1:n2)-f(l1:l2,pos+sgn*4,n1:n2)))
!
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in y-direction'
        endif
      elseif (j==3) then
        if (nzgrid/=1) then
          fac=1./12.*dz_1(pos)
          df = fac*(-sgn*25*f(l1:l2,m1:m2,pos)&
                    +sgn*48*f(l1:l2,m1:m2,pos+sgn*1)&
                    -sgn*36*f(l1:l2,m1:m2,pos+sgn*2)&
                    +sgn*16*f(l1:l2,m1:m2,pos+sgn*3)&
                    -sgn*3 *f(l1:l2,m1:m2,pos+sgn*4))
!
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice: Degenerate case in z-direction'
        endif
      endif
!
    endsubroutine der_onesided_4_slice_other
!***********************************************************************
    subroutine der_onesided_4_slice_other_pt(f,sgn,df,lll,mmm,nnn,j)
!
!  One sided derivative is calculated
!  at one point (lll,mmm,nnn).
!
!  15-oct-09/Natalia: coded.
!  15-oct-09/axel: changed file name to shorter version
!
      real, dimension (mx,my,mz) :: f
      real :: df
      real :: fac
      integer :: pos,lll,mmm,nnn,sgn,j
!
      intent(in)  :: f,lll,mmm,nnn,sgn,j
      intent(out) :: df
!
      if (j==1) then
        pos=lll
        if (nxgrid/=1) then
          fac=1./12.*dx_1(pos)
          df = fac*(-sgn*25*f(pos,mmm,nnn)&
                    +sgn*48*f(pos+sgn*1,mmm,nnn)&
                    -sgn*36*f(pos+sgn*2,mmm,nnn)&
                    +sgn*16*f(pos+sgn*3,mmm,nnn)&
                    -sgn*3 *f(pos+sgn*4,mmm,nnn))
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice_other_pt: Degenerate case in x-direction'
        endif
      elseif (j==2) then
        pos=mmm
        if (nygrid/=1) then
          fac=1./12.*dy_1(pos)
          df = fac*(-sgn*25*(f(lll,pos,nnn)-f(lll,pos+sgn*1,nnn))&
                    +sgn*23*(f(lll,pos+sgn*1,nnn)-f(lll,pos+sgn*2,nnn))&
                    -sgn*13*(f(lll,pos+sgn*2,nnn)-f(lll,pos+sgn*3,nnn))&
                    +sgn* 3*(f(lll,pos+sgn*3,nnn)-f(lll,pos+sgn*4,nnn)))
!
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice_other_pt: Degenerate case in y-direction'
        endif
      elseif (j==3) then
        pos=nnn
        if (nzgrid/=1) then
          fac=1./12.*dz_1(pos)
          df = fac*(-sgn*25*f(lll,mmm,pos)&
                    +sgn*48*f(lll,mmm,pos+sgn*1)&
                    -sgn*36*f(lll,mmm,pos+sgn*2)&
                    +sgn*16*f(lll,mmm,pos+sgn*3)&
                    -sgn*3 *f(lll,mmm,pos+sgn*4))
!
        else
          df=0.
          if (ip<=5) print*, 'der_onesided_4_slice_other_pt: Degenerate case in z-direction'
        endif
      endif
    endsubroutine der_onesided_4_slice_other_pt
!***********************************************************************
    subroutine finalize_deriv()
!
!  Dummy
!
    endsubroutine finalize_deriv
!***********************************************************************
    subroutine deri_3d_inds(f,df,inds,j,lignored,lnometric)
!
!  dummy routine for compatibility
!
!  26-mar-12/MR: coded
!
      real, dimension (mx,my,mz)          :: f
      real, dimension (nx)                :: df
      integer                             :: j
      logical,                   optional :: lignored, lnometric
      integer, dimension(nx)              :: inds
!
      intent(in)  :: f,j,inds,lignored,lnometric
      intent(out) :: df
!
      call fatal_error('deri_3d_inds','Upwinding not implemented for nonuniform grids')
!
! dummy computation to avoid compiler warnings of unused variables
      if (present(lignored).and.present(lnometric)) &
          df  = inds + f(l1:l2,1,1) + j
!
    endsubroutine deri_3d_inds
!************************************************************************
    logical function heatflux_deriv_x(f, inh, fac, topbot)
!
!   dummy routine
!
!  17-apr-12/MR: coded
!
      use General, only: keep_compiler_quiet
!
      real, dimension(mx,my,mz,mfarray), intent(IN):: f
      real, dimension(my,mz)           , intent(IN):: inh
      real                             , intent(IN):: fac
      integer                          , intent(IN):: topbot
!
      heatflux_deriv_x = .true.
      call keep_compiler_quiet(f)
      call keep_compiler_quiet(inh)
      call keep_compiler_quiet(fac)
      call keep_compiler_quiet(topbot)
!
    endfunction heatflux_deriv_x
!***********************************************************************
 endmodule Deriv
