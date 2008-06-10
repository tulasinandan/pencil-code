;;
;;  $Id: yder_6th_ghost.pro,v 1.16 2008-06-10 17:22:24 ajohan Exp $
;;
;;  First derivative d/dy
;;  - 6th-order
;;  - with ghost cells
;;  - on potentially non-equidistant grid
;;
function yder,f,ghost=ghost,bcx=bcx,bcy=bcy,bcz=bcz,param=param,t=t
  COMPILE_OPT IDL2,HIDDEN
;
  common cdat,x,y,z
  common cdat_nonequidist,dx_1,dy_1,dz_1,dx_tilde,dy_tilde,dz_tilde,lequidist
  common cdat_coords,coord_system
;
;  Default values.
;
  default, ghost, 0
;
;  Calculate nx, ny, and nz, based on the input array size.
;
  s=size(f) & d=make_array(size=s)
  nx=s[1] & ny=s[2] & nz=s[3]
;
  xx=spread(x,[1,2],[ny,nz])
;
;  Check for degenerate case (no y-extension).
;
  if (n_elements(lequidist) ne 3) then lequidist=[1,1,1]
  if (ny eq 1) then return,fltarr(nx,ny,nz)
;
;  Determine location of ghost zones, assume nghost=3 for now.
;
  l1=3 & l2=nx-4 & m1=3 & m2=ny-4 & n1=3 & n2=nz-4
;
  if (lequidist[1]) then begin
    dy2=1./(60.*(y[4]-y[3]))
  endif else begin
    dy2=dy_1[m1:m2]/60.
  endelse
;
  if (s[0] eq 3) then begin
    if (m2 gt m1) then begin
      if (lequidist[1] eq 0) then dy2=spread(dy2,[0,2],[s[1],s[3]])
      ; will also work on slices like yder(ss[10,*,n1:n2])
      d[l1:l2,m1:m2,n1:n2]=dy2* $
          ( +45.*(f[l1:l2,m1+1:m2+1,n1:n2]-f[l1:l2,m1-1:m2-1,n1:n2]) $
             -9.*(f[l1:l2,m1+2:m2+2,n1:n2]-f[l1:l2,m1-2:m2-2,n1:n2]) $
                +(f[l1:l2,m1+3:m2+3,n1:n2]-f[l1:l2,m1-3:m2-3,n1:n2]) )
      if (not(coord_system eq 'cartesian')) then d=d/xx
    endif else begin
      d[l1:l2,m1:m2,n1:n2]=0.
    endelse
;
  endif else if (s[0] eq 4) then begin
;
    if (m2 gt m1) then begin

      if (lequidist[1] eq 0) then dy2=spread(dy2,[0,2,3],[s[1],s[3],s[4]])
      ; will also work on slices like yder(uu[10,*,*,*,])
      d[l1:l2,m1:m2,n1:n2,*]=dy2* $
          ( +45.*(f[l1:l2,m1+1:m2+1,n1:n2,*]-f[l1:l2,m1-1:m2-1,n1:n2,*]) $
             -9.*(f[l1:l2,m1+2:m2+2,n1:n2,*]-f[l1:l2,m1-2:m2-2,n1:n2,*]) $
                +(f[l1:l2,m1+3:m2+3,n1:n2,*]-f[l1:l2,m1-3:m2-3,n1:n2,*]) )
      if (not(coord_system eq 'cartesian')) then $
          d[l1:l2,n1:n2,*,0:s[4]-1]=d[l1:l2,n1:n2,*,0:s[4]-1]/xx
    endif else begin
      d[l1:l2,m1:m2,n1:n2,*]=0.
    endelse
;
  endif else begin
    print, 'error: yder_6th_ghost not implemented for ', $
        strtrim(s[0],2), '-D arrays'
  endelse
;
;  Set ghost zones.
;
  if (ghost) then d=pc_setghost(d,bcx=bcx,bcy=bcy,bcz=bcz,param=param,t=t)
;
  return, d
;
end
