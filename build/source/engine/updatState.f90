module updatState_module
USE nrtype
! physical constants
USE multiconst,only:&
                    Tfreeze,     & ! freezing point of pure water  (K)
                    iden_air,    & ! intrinsic density of air      (kg m-3)
                    iden_ice,    & ! intrinsic density of ice      (kg m-3)
                    iden_water,  & ! intrinsic density of water    (kg m-3)
                    gravity,     & ! gravitational acceleteration  (m s-2)
                    LH_fus         ! latent heat of fusion         (J kg-1)
! named variables
USE data_struc,only:ix_soil,ix_snow ! named variables for snow and soil
implicit none
private
public::updateSnow
public::updateSoil
contains

 ! ************************************************************************************************
 ! new subroutine: compute phase change impacts on matric head and volumetric liquid water and ice
 ! ************************************************************************************************
 subroutine updateSnow(&
                       ! input
                       mLayerTemp       ,& ! intent(in): temperature vector (K)
                       snowfrz_scale    ,& ! intent(in): scaling parameter for the snow freezing curve (K-1)
                       ! input/output
                       mLayerVolFracLiq ,& ! intent(inout): volumetric fraction of liquid water (-)
                       mLayerVolFracIce ,& ! intent(inout): volumetric fraction of ice (-)
                       ! output
                       fLiq             ,& ! intent(out): fraction of liquid water (-)
                       err,message)        ! intent(out): error control
 ! utility routines
 USE snow_utils_module,only:fracliquid     ! compute volumetric fraction of liquid water
 implicit none
 ! input variables
 real(dp),intent(in)           :: mLayerTemp           ! estimate of temperature (K)
 real(dp),intent(in)           :: snowfrz_scale        ! scaling parameter for the snow freezing curve (K-1)
 ! input/output variables
 real(dp),intent(inout)        :: mLayerVolFracLiq     ! volumetric fraction of liquid water (-)
 real(dp),intent(inout)        :: mLayerVolFracIce     ! volumetric fraction of ice (-)
 ! output variables
 real(dp),intent(out)          :: fLiq                 ! fraction of liquid water (-)
 ! error control
 integer(i4b),intent(out)      :: err                  ! error code
 character(*),intent(out)      :: message              ! error message
 ! define local variables
 real(dp)                      :: theta                ! liquid water equivalent of total water (-)
 ! initialize error control
 err=0; message="updateSnow/"

 ! compute liquid water equivalent of total water (liquid plus ice)
 theta = mLayerVolFracIce*(iden_ice/iden_water) + mLayerVolFracLiq

 ! compute the volumetric fraction of liquid water and ice (-)
 fLiq = fracliquid(mLayerTemp,snowfrz_scale)
 mLayerVolFracLiq = fLiq*theta
 mLayerVolFracIce = (1._dp - fLiq)*theta*(iden_water/iden_ice)
 !print*, 'theta - (mLayerVolFracIce*(iden_ice/iden_water) + mLayerVolFracLiq) = ', theta - (mLayerVolFracIce*(iden_ice/iden_water) + mLayerVolFracLiq)

 !write(*,'(a,1x,4(f20.10,1x))') 'in updateSnow: fLiq, theta, mLayerVolFracIce = ', &
 !                                               fLiq, theta, mLayerVolFracIce
 !pause

 endsubroutine updateSnow

 ! ************************************************************************************************
 ! new subroutine: compute phase change impacts on matric head and volumetric liquid water and ice
 ! ************************************************************************************************
 subroutine updateSoil(&
                       ! input
                       mLayerTemp       ,& ! intent(in): temperature vector (K)
                       mLayerMatricHead ,& ! intent(in): matric head (m)
                       vGn_alpha        ,& ! intent(in): van Genutchen "alpha" parameter
                       vGn_n            ,& ! intent(in): van Genutchen "n" parameter
                       theta_sat        ,& ! intent(in): soil porosity (-)
                       theta_res        ,& ! intent(in): soil residual volumetric water content (-)
                       vGn_m            ,& ! intent(in): van Genutchen "m" parameter (-)
                       ! output
                       mLayerVolFracLiq ,& ! intent(out): volumetric fraction of liquid water (-)
                       mLayerVolFracIce ,& ! intent(out): volumetric fraction of ice (-)
                       dMatric_dTk      ,& ! intent(out): derivative in matric head w.r.t. temperature (m K-1)
                       dTk_dMatric      ,& ! intent(out): derivative in temperature w.r.t. matric head (K m-1)
                       err,message)        ! intent(out): error control
 ! utility routines
 USE soil_utils_module,only:volFracLiq     ! compute volumetric fraction of liquid water based on matric head
 USE soil_utils_module,only:matricHead     ! compute the matric head based on volumetric liquid water content
 implicit none
 ! input variables
 real(dp),intent(in)           :: mLayerTemp           ! estimate of temperature (K)
 real(dp),intent(in)           :: mLayerMatricHead     ! matric head (m)
 real(dp),intent(in)           :: vGn_alpha            ! van Genutchen "alpha" parameter
 real(dp),intent(in)           :: vGn_n                ! van Genutchen "n" parameter
 real(dp),intent(in)           :: theta_sat            ! soil porosity (-)
 real(dp),intent(in)           :: theta_res            ! soil residual volumetric water content (-)
 real(dp),intent(in)           :: vGn_m                ! van Genutchen "m" parameter (-)
 ! output variables
 real(dp),intent(out)          :: mLayerVolFracLiq     ! volumetric fraction of liquid water (-)
 real(dp),intent(out)          :: mLayerVolFracIce     ! volumetric fraction of ice (-)
 real(dp),intent(out)          :: dMatric_dTk          ! derivative in matric head w.r.t. temperature (m K-1)
 real(dp),intent(out)          :: dTk_dMatric          ! derivative in temperature w.r.t. matric head (K m-1)
 integer(i4b),intent(out)      :: err                  ! error code
 character(*),intent(out)      :: message              ! error message
 ! define local variables
 real(dp)                      :: vTheta               ! fractional volume of total water (-)
 real(dp)                      :: psiLiq               ! matric head associated with liquid water (m)
 real(dp)                      :: TcSoil               ! critical soil temperature when all water is unfrozen (K)
 real(dp)                      :: xConst               ! constant in the freezing curve function (m K-1)
 ! initialize error control
 err=0; message="updateSoil/"

 ! compute fractional **volume** of total water (liquid plus ice)
 vTheta = volFracLiq(mLayerMatricHead,vGn_alpha,theta_res,theta_sat,vGn_n,vGn_m)
 if(vTheta > theta_sat)then; err=20; message=trim(message)//'volume of liquid and ice exceeds porosity'; return; endif

 ! compute the critical soil temperature where all water is unfrozen (K)
 ! (eq 17 in Dall'Amico 2011)
 TcSoil = Tfreeze + mLayerMatricHead*gravity*Tfreeze/LH_fus  ! (NOTE: J = kg m2 s-2, so LH_fus is in units of m2 s-2)

 ! *** compute volumetric fraction of liquid water and ice for partially frozen soil
 if(mLayerTemp < TcSoil)then ! (check if soil temperature is less than the critical temperature)

  ! - volumetric liquid water content (-)
  xConst           = LH_fus/(gravity*TcSoil)                             ! m K-1 (NOTE: J = kg m2 s-2)
  psiLiq           = mLayerMatricHead + xConst*(mLayerTemp - TcSoil)     ! eq 19 in Dall'Amico 2011
  mLayerVolFracLiq = volFracLiq(psiLiq,vGn_alpha,theta_res,theta_sat,vGn_n,vGn_m)

  ! - volumetric ice content (-)
  mLayerVolFracIce = vTheta - mLayerVolFracLiq
  
  ! - compute the derivative in matric head w.r.t. temperature (m K-1)
  dMatric_dTk = xConst  
  dTk_dMatric = 1._dp/xConst  

 ! *** compute volumetric fraction of liquid water and ice for unfrozen soil
 else

  ! all water is unfrozen
  mLayerVolFracLiq = vTheta
  mLayerVolFracIce = 0._dp

  ! compute the derivative in matric head w.r.t. temperature (m K-1)
  dMatric_dTk = 0._dp
  dTk_dMatric = 0._dp

 endif  ! (check if soil is partially frozen)

 end subroutine updateSoil

end module updatState_module
