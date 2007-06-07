!*****************************************************************************
subroutine tsy_trace(re,rc,xlati1,phi1,t,ps,parmod,imod,np, &
     npf1,dssa,bba,volume1,ro1,xmlt1,bo1,ra)
!*****************************************************************************
! Routine does field line tracing in Tsyganenko field. For a given xlati1 and
! phi1, output distance from the ionosphere, magnetic field, flux tube volume
! per unit flux and equatorial crossing point.
! npf1 is the number of point along that field line. npf1=0 if this is an open
! field line.
!
! Input: re,rc,xlati1,phi1,t,ps,parmod,imod,np
! Output: npf1,dssa,bba,volume1,ro1,xmlt1,bo1    ! bba, bo1 in Tesla 

  use ModSort, ONLY: sort_quick
  use rbe_grid
  implicit none
  external tsyndipoleSM
  
  integer, parameter :: nd=3
  integer imod,np,npf1,i,j,n,ii,iopt,ind(np)
  real, intent(out)   :: ra(np) 
  integer:: ieq
  real re,rc,xlati1,phi1,t,ps,parmod(10),dssa(np),bba(np),volume1,ro1,xmlt1,bo1
  real xa(np),ya(np),za(np),pi,x0(3),xend(3),f(3),t0,tend,h,h1,aza(np)
  real dir,pas,xwrk(4,nd),rlim,b_mid,dss(np),ss,yint(np)

  pi=acos(-1.)
  iopt=1               ! dummy variable for tsy models
  rlim=30.
  dir=-1.              ! start fieldline tracing from Northern hemisphere
  pas=0.1              ! fieldline tracing step in RE
  h=pas*dir

! initial
  x0(1)=rc*cos(xlati1)*cos(phi1)  ! sm x
  x0(2)=rc*cos(xlati1)*sin(phi1)  ! sm y
  x0(3)=rc*sin(xlati1)            ! sm z
  t0=0.
  npf1=1
  call tsyndipoleSM(imod,iopt,parmod,ps,t,x0(1),x0(2),x0(3),f(1),f(2),f(3))
  bba(1)=sqrt(f(1)*f(1)+f(2)*f(2)+f(3)*f(3))*1.e-9   ! B in T
  xa(1)=x0(1)
  ya(1)=x0(2)
  za(1)=x0(3)
  ra(1)=sqrt(xa(1)*xa(1)+ya(1)*ya(1)+za(1)*za(1))
  dssa(1)=0.

! start tracing
  trace: do
     call rk4(tsyndipoleSM,imod,iopt,parmod,ps,t,t0, &
              h,x0,xend,xwrk,nd,f,tend)
     npf1=npf1+1
     ra(npf1)=sqrt(xend(1)*xend(1)+xend(2)*xend(2)+xend(3)*xend(3))
     xa(npf1)=xend(1)
     ya(npf1)=xend(2)
     za(npf1)=xend(3)
     bba(npf1)=sqrt(f(1)*f(1)+f(2)*f(2)+f(3)*f(3))*1.e-9    ! B in T
     dssa(npf1)=dssa(npf1-1)+abs(h)

     if (ra(npf1).gt.rlim.or.npf1.gt.np) then
        npf1=0              ! open field line
        exit trace                                                       
     endif

     if (ra(npf1).le.rc) then               ! at south hemisphere
        ! reduce step size such that ra(npf1) is at rc
        h1=(ra(npf1-1)-rc)/(ra(npf1-1)-ra(npf1))
        ra(npf1)=rc
        xa(npf1)=xa(npf1-1)+(xend(1)-xa(npf1-1))*h1
        ya(npf1)=ya(npf1-1)+(xend(2)-ya(npf1-1))*h1
        za(npf1)=za(npf1-1)+(xend(3)-za(npf1-1))*h1
        call tsyndipoleSM(imod,iopt,parmod,ps,t, &
                          xa(npf1),ya(npf1),za(npf1),f(1),f(2),f(3))
        bba(npf1)=sqrt(f(1)*f(1)+f(2)*f(2)+f(3)*f(3))*1.e-9   ! B in T
        dssa(npf1)=dssa(npf1-1)+abs(h)*h1

        ! Calculate the flux tube volume per magnetic flux (volume1)
        n=npf1-1 ! n = no. of intervals from N(rc) to S(rc) hemisphere
        do ii=1,n
           b_mid=0.5*(bba(ii)+bba(ii+1))
           dss(ii)=dssa(ii+1)-dssa(ii)
           yint(ii)=1./b_mid
        enddo
        call closed(1,n,yint,dss,ss)  ! use closed form
        if (i.ge.1.and.i.le.ir) volume1=ss*re   ! volume / flux
        exit trace      ! finish tracing this field line
     endif

     x0(1:nd)=xend(1:nd)
     t0=tend
  enddo trace           ! continue tracing along this field line

! find the equatorial crossing point
  aza(1:npf1)=abs(za(1:npf1))

  call sort_quick(npf1,aza,ind)    ! find the equatorial crossing point

  ieq=ind(1)
  ro1=ra(ieq)
  xmlt1=atan2(-ya(ieq),-xa(ieq))*12./pi   ! mlt in hr
  if (xmlt1.lt.0.) xmlt1=xmlt1+24.
  bo1=bba(ieq)

end subroutine tsy_trace

!==============================================================================

subroutine mhd_trace (re,iLat,iLon,parmod,np, &
     nAlt,FieldLength_I,Bfield_I,volume1,ro1,xmlt1,bo1,RadialDist_I)

  use rbe_grid
  use ModGmRb
  use ModNumConst, ONLY: cPi

  implicit none

  integer,intent(in)  :: iLat,iLon,np
  real,   intent(in)  :: re,parmod(10)
  ! bba, bo1 in Tesla 
  real,   intent(out) :: RadialDist_I(np),FieldLength_I(np),Bfield_I(np),&
                         volume1,ro1,xmlt1,bo1
  integer,intent(out) :: nAlt
  
  integer, parameter :: nd=3
  integer ::i,j,n,ii,iopt,ind(np),iPoint,iAlt
  integer, parameter :: I_=1,S_=2,R_=3,B_=4
  
  real xa(np),ya(np),za(np),x0(3),xend(3),f(3),t0,tend,h,h1,aza(np)
  real dir,pas,xwrk(4,nd),rlim,Bmid,dss(np),ss,yint(np)
  Logical IsFoundLine
  !----------------------------------------------------------------------------
  

  ! Put BufferLine_VI indexed by line number into StateLine_CIIV
  
  iAlt = 1
  IsFoundLine=.false.
  FieldTrace: do iPoint = 1,nPoint
     if (iLineIndex_II(iLat,iLon) == StateLine_VI(I_,iPoint))then
        !when line index found, fill in output arrays
        Bfield_I(iAlt)     = StateLine_VI(B_,iPoint)
        FieldLength_I(iAlt)= StateLine_VI(S_,iPoint)
        RadialDist_I(iAlt) = StateLine_VI(R_,iPoint)
        
        iAlt = iAlt+1
        IsFoundLine=.true.
     elseif (iLineIndex_II(iLat,iLon) /= StateLine_VI(I_,iPoint) &
          .and. IsFoundLine) then
        exit FieldTrace 
     endif
  end do FieldTrace

  nAlt = iAlt-1
  
  !Check if FieldLine is open
  if (.not. IsFoundLine) then
     nAlt=0
     return
  endif

  ro1=sqrt(sum(StateIntegral_IIV(iLat,iLon,1:2)**2.0))
  xmlt1=&
       atan2(-StateIntegral_IIV(iLat,iLon,2),-StateIntegral_IIV(iLat,iLon,1))&
       *12./cPi   ! mlt in hr
  if (xmlt1.lt.0.) xmlt1=xmlt1+24.
  bo1=StateIntegral_IIV(iLat,iLon,3)

  ! Calculate the flux tube volume per magnetic flux (volume1)
  
  do ii=1,nAlt-1
     Bmid=0.5*(Bfield_I(ii)+Bfield_I(ii+1))
     dss(ii)=FieldLength_I(ii+1)-FieldLength_I(ii)
     yint(ii)=1./Bmid
  enddo
  call closed(1,n,yint,dss,ss)  ! use closed form
  if (i.ge.1.and.i.le.ir) volume1=ss*re   ! volume / flux
  
  end subroutine mhd_trace