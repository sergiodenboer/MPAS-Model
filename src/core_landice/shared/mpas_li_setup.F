! Copyright (c) 2013,  Los Alamos National Security, LLC (LANS)
! and the University Corporation for Atmospheric Research (UCAR).
!
! Unless noted otherwise source code is licensed under the BSD license.
! Additional copyright and license information can be found in the LICENSE file
! distributed with this code, or at http://mpas-dev.github.com/license.html
!

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  li_setup
!
!> \brief MPAS land ice setup module
!> \author Matt Hoffman
!> \date   17 April 2011
!> \details
!>  This module contains various subroutines for
!>  setting up the land ice core.
!
!-----------------------------------------------------------------------
module li_setup

   use mpas_derived_types
   use mpas_pool_routines
   use mpas_kind_types
   use mpas_dmpar

   implicit none
   private
   save

   !--------------------------------------------------------------------
   !
   ! Public parameters
   !
   !--------------------------------------------------------------------

   type (mpas_pool_type), pointer :: liConfigs  !< Public parameter: pool of config options

   public :: liConfigs

   !--------------------------------------------------------------------
   !
   ! Public member functions
   !
   !--------------------------------------------------------------------
   public :: li_setup_config_options, &
             li_setup_vertical_grid, &
             li_setup_sign_and_index_fields

   !--------------------------------------------------------------------
   !
   ! Private module variables
   !
   !--------------------------------------------------------------------



!***********************************************************************

contains


!***********************************************************************
!
!  routine li_setup_config_options
!
!> \brief   Makes any setup changes needed based on chosen config options
!> \author  Matt Hoffman
!> \date    16 April 2014
!> \details
!>  This routine makes any adjustments as needed based on which
!>  config options were chosen.
!
!-----------------------------------------------------------------------

   subroutine li_setup_config_options( domain, err )

      use mpas_timekeeping

      !-----------------------------------------------------------------
      ! input variables
      !-----------------------------------------------------------------

      !-----------------------------------------------------------------
      ! input/output variables
      !-----------------------------------------------------------------
      type (domain_type), intent(inout) :: domain  !< Input/Output: domain object

      !-----------------------------------------------------------------
      ! output variables
      !-----------------------------------------------------------------
      integer, intent(out) :: err            !< Output: error flag

      !-----------------------------------------------------------------
      ! local variables
      !-----------------------------------------------------------------

      err = 0

      ! Make config pool publicly available in this module
      liConfigs => domain % configs


      ! Print this run's configs to the err log file
      write(stderrUnit,*) "MPASLI is using the following configuration:"
      write(stderrUnit,*) "============================================"
      call mpas_pool_print_summary(liConfigs, MPAS_POOL_CONFIG)
      write(stderrUnit,*) "============================================"
      write(stderrUnit,*) ""

      ! ---
      ! Config-specific setup occurs below
      ! ---


   !--------------------------------------------------------------------
   end subroutine li_setup_config_options



!***********************************************************************
!
!  routine li_setup_vertical_grid
!
!> \brief   Initializes vertical coord system
!> \author  Matt Hoffman
!> \date    20 April 2012
!> \details
!>  This routine initializes the vertical coord system.
!
!-----------------------------------------------------------------------

   subroutine li_setup_vertical_grid(meshPool, geometryPool, err)

      !-----------------------------------------------------------------
      !
      ! input variables
      !
      !-----------------------------------------------------------------

      !-----------------------------------------------------------------
      !
      ! input/output variables
      !
      !-----------------------------------------------------------------
      type (mpas_pool_type), intent(inout) :: meshPool  !< Input/Output: mesh object
      type (mpas_pool_type), intent(inout) :: geometryPool  !< Input/Output: geometry object

      !-----------------------------------------------------------------
      !
      ! output variables
      !
      !-----------------------------------------------------------------

      integer, intent(out) :: err            !< Output: error flag

      !-----------------------------------------------------------------
      !
      ! local variables
      !
      !-----------------------------------------------------------------
      ! Pool pointers
      integer, pointer :: nVertLevels ! Dimensions
      real (kind=RKIND), dimension(:), pointer :: layerThicknessFractions, layerCenterSigma, layerInterfaceSigma
      real (kind=RKIND), dimension(:), pointer :: thickness
      real (kind=RKIND), dimension(:,:), pointer :: layerThickness1, layerThickness2
      logical, pointer :: config_do_restart
      ! Truly locals
      integer :: k
      real (kind=RKIND) :: fractionTotal

      ! Get pool stuff
      call mpas_pool_get_config(liConfigs, 'config_do_restart', config_do_restart)
      call mpas_pool_get_dimension(meshPool, 'nVertLevels', nVertLevels)
      ! layerThicknessFractions is provided by input
      call mpas_pool_get_array(meshPool, 'layerThicknessFractions', layerThicknessFractions)
      call mpas_pool_get_array(meshPool, 'layerCenterSigma', layerCenterSigma)
      call mpas_pool_get_array(meshPool, 'layerInterfaceSigma', layerInterfaceSigma)
      call mpas_pool_get_array(geometryPool, 'thickness', thickness)
      call mpas_pool_get_array(geometryPool, 'layerThickness', layerThickness1, timeLevel=1)
      call mpas_pool_get_array(geometryPool, 'layerThickness', layerThickness2, timeLevel=2)

      ! Check that layerThicknessFractions are valid
      ! TODO - switch to having the user input the sigma levels instead???
      if (.not. config_do_restart) then   ! This would be applied an additional time on each restart, messing up the vertical levels (very, very slightly)
      fractionTotal = sum(layerThicknessFractions)
      if (fractionTotal /= 1.0_RKIND) then
         if (abs(fractionTotal - 1.0_RKIND) > 0.001_RKIND) then
            write(stderrUnit,*) 'Error: The sum of layerThicknessFractions is different from 1.0 by more than 0.001.'
            err = 1
         end if
         write (stdoutUnit,*) 'Adjusting upper layerThicknessFrac by small amount because sum of layerThicknessFractions is slightly different from 1.0.'
         layerThicknessFractions(1) = layerThicknessFractions(1) - (fractionTotal - 1.0_RKIND)
      endif
      endif

      ! layerCenterSigma is the fractional vertical position (0-1) of each layer center, with 0.0 at the ice surface and 1.0 at the ice bed
      ! layerInterfaceSigma is the fractional vertical position (0-1) of each layer interface, with 0.0 at the ice surface and 1.0 at the ice bed.  Interface 1 is the surface, interface 2 is between layers 1 and 2, etc., and interface nVertLevels+1 is the bed.
      layerCenterSigma(1) = 0.5_RKIND * layerThicknessFractions(1)
      layerInterfaceSigma(1) = 0.0_RKIND
      do k = 2, nVertLevels 
         layerCenterSigma(k) = layerCenterSigma(k-1) + 0.5_RKIND * layerThicknessFractions(k-1) &
            + 0.5_RKIND * layerThicknessFractions(k)
         layerInterfaceSigma(k) = layerInterfaceSigma(k-1) + layerThicknessFractions(k-1)
      end do
      layerInterfaceSigma(nVertLevels+1) = 1.0_RKIND

      ! Also, initialize the layerThickness field
      do k = 1, nVertLevels
         layerThickness1(k,:) = thickness(:) * layerThicknessFractions(k)
      enddo
      layerThickness2 = layerThickness1

   !--------------------------------------------------------------------
   end subroutine li_setup_vertical_grid



!***********************************************************************
!
!  routine li_setup_sign_and_index_fields
!
!> \brief   Determines signs for various mesh items
!> \author  Matt Hoffman - based on code by Doug Jacobsen
!> \date    20 April 2012
!> \details
!>  This routine determines the sign for various mesh items.
!
!-----------------------------------------------------------------------
   subroutine li_setup_sign_and_index_fields(meshPool)

      !-----------------------------------------------------------------
      !
      ! input variables
      !
      !-----------------------------------------------------------------
      type (mpas_pool_type), intent(in) :: meshPool  !< Input: mesh object

      !-----------------------------------------------------------------
      !
      ! input/output variables
      !
      !-----------------------------------------------------------------

      !-----------------------------------------------------------------
      !
      ! output variables
      !
      !-----------------------------------------------------------------

      !-----------------------------------------------------------------
      !
      ! local variables
      !
      !-----------------------------------------------------------------
      ! Pool pointers
      integer, pointer :: nCells !, nVertices, vertexDegree
      integer, dimension(:), pointer :: nEdgesOnCell
      integer, dimension(:,:), pointer :: edgesOnCell, cellsOnEdge !, edgesOnVertex, cellsOnVertex, verticesOnCell, verticesOnEdge
      integer, dimension(:,:), pointer :: edgeSignOnCell !, edgeSignOnVertex, kiteIndexOnCell
      ! Truly locals
       integer :: iCell, iEdge, iVertex, i, j, k

      ! Get pool stuff
      call mpas_pool_get_dimension(meshPool, 'nCells', nCells)
      call mpas_pool_get_array(meshPool, 'nEdgesOnCell', nEdgesOnCell)
      call mpas_pool_get_array(meshPool, 'edgesOnCell', edgesOnCell)
      call mpas_pool_get_array(meshPool, 'cellsOnEdge', cellsOnEdge)
      call mpas_pool_get_array(meshPool, 'edgeSignOnCell', edgeSignOnCell)

       edgeSignOnCell = 0.0_RKIND
       !edgeSignOnVertex = 0.0_RKIND
       !kiteIndexOnCell = 0.0_RKIND
       ! If needed, edgeSignOnVertex and kiteIndexOnCell can also be setup here.

       do iCell = 1, nCells
         do i = 1, nEdgesOnCell(iCell)
           iEdge = edgesOnCell(i, iCell)
           !iVertex = verticesOnCell(i, iCell)

           ! Vector points from cell 1 to cell 2
           if(iCell == cellsOnEdge(1, iEdge)) then
             edgeSignOnCell(i, iCell) = -1
           else
             edgeSignOnCell(i, iCell) =  1
           end if

           !do j = 1, vertexDegree
           !  if(cellsOnVertex(j, iVertex) == iCell) then
           !    kiteIndexOnCell(i, iCell) = j
           !  end if
           !end do
         end do
       end do

       !do iVertex = 1, nVertices
       !  do i = 1, vertexDegree
       !    iEdge = edgesOnVertex(i, iVertex)
       !
       !    ! Vector points from vertex 1 to vertex 2
       !    if(iVertex == verticesOnEdge(1, iEdge)) then
       !      edgeSignOnVertex(i, iVertex) = -1
       !    else
       !      edgeSignOnVertex(i, iVertex) =  1
       !    end if
       !  end do
       !end do

   !--------------------------------------------------------------------
   end subroutine li_setup_sign_and_index_fields



!***********************************************************************
!***********************************************************************
! Private subroutines:
!***********************************************************************
!***********************************************************************



end module li_setup