/////////////////////////////////////////////////////////////////////////////////////////////
// Copyright 2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");// you may not use this file except in compliance with the License.// You may obtain a copy of the License at//// http://www.apache.org/licenses/LICENSE-2.0//// Unless required by applicable law or agreed to in writing, software// distributed under the License is distributed on an "AS IS" BASIS,// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.// See the License for the specific language governing permissions and// limitations under the License.
/////////////////////////////////////////////////////////////////////////////////////////////
#include "CPUTCamera.h"
#include "CPUTFrustum.h"

// Constructor
//-----------------------------------------------------------------------------
CPUTCamera::CPUTCamera() : 
    mFov(45.0f * 3.14159265f/180.0f),
    mNearPlaneDistance(1.0f),
    mFarPlaneDistance(100.0f),
    mAspectRatio(16.0f/9.0f)
{
    // default maya position (roughly)
    SetPosition( 1.0f, 0.8f, 1.0f );
}

// Load
//-----------------------------------------------------------------------------
CPUTResult CPUTCamera::LoadCamera(CPUTConfigBlock *pBlock, int *pParentID)
{
    // TODO: Have render node load common properties.
    CPUTResult result = CPUT_SUCCESS;

    mName = pBlock->GetValueByName(_L("name"))->ValueAsString();
    *pParentID = pBlock->GetValueByName(_L("parent"))->ValueAsInt();

    mFov = pBlock->GetValueByName(_L("FieldOfView"))->ValueAsFloat();
    mFov *= (3.14159265f/180.0f);
    mNearPlaneDistance = pBlock->GetValueByName(_L("NearPlane"))->ValueAsFloat();
    mFarPlaneDistance = pBlock->GetValueByName(_L("FarPlane"))->ValueAsFloat();

    LoadParentMatrixFromParameterBlock( pBlock );

    return result;
}

//-----------------------------------------------------------------------------
void CPUTCamera::SetAspectRatio(const float aspectRatio)
{
    mAspectRatio = aspectRatio;
}

//-----------------------------------------------------------------------------
void CPUTCamera::LookAt( float xx, float yy, float zz )
{
    float3 pos;
    GetPosition( &pos);

    float3 lookPoint(xx, yy, zz);
    float3 look  = (lookPoint - pos).normalize();
    float3 right = cross3(float3(0.0f,1.0f,0.0f), look).normalize(); // TODO: simplicy algebraically
    float3 up    = cross3(look, right);
    
    mParentMatrix = float4x4(
        right.x, right.y, right.z, 0.0f,
           up.x,    up.y,    up.z, 0.0f,
         look.x,  look.y,  look.z, 0.0f,
          pos.x,   pos.y,   pos.z, 1.0f
    );
}

//-----------------------------------------------------------------------------
void CPUTCamera::SetFov(const float fov)
{
    mFov = fov;
}

#define KEY_DOWN(vk) ((GetAsyncKeyState(vk) & 0x8000)?1:0)
//-----------------------------------------------------------------------------
void CPUTCameraControllerFPS::Update(float deltaSeconds)
{
    float speed = mfMoveSpeed * deltaSeconds;
    speed *= KEY_DOWN( VK_LSHIFT ) ? 10.0f : KEY_DOWN( VK_LCONTROL) ? 0.1f : 1.0f;

    float4x4 *pParentMatrix = mpCamera->GetParentMatrix();

    float3 vRight(pParentMatrix->getXAxis());
    float3 vUp(pParentMatrix->getYAxis());
    float3 vLook(pParentMatrix->getZAxis());
    float3 vPositionDelta(0.0f);

    if(CPUTOSServices::GetOSServices()->DoesWindowHaveFocus())
    {
        if(KEY_DOWN('W')) { vPositionDelta +=  vLook *  speed;}
        if(KEY_DOWN('A')) { vPositionDelta += vRight * -speed;}
        if(KEY_DOWN('S')) { vPositionDelta +=  vLook * -speed;}
        if(KEY_DOWN('D')) { vPositionDelta += vRight *  speed;}
        if(KEY_DOWN('E')) { vPositionDelta +=    vUp *  speed;}
        if(KEY_DOWN('Q')) { vPositionDelta +=    vUp * -speed;}
    }
    float x,y,z;
    mpCamera->GetPosition( &x, &y, &z );
    mpCamera->SetPosition( x+vPositionDelta.x, y+vPositionDelta.y, z+vPositionDelta.z );
    mpCamera->Update();
}

//-----------------------------------------------------------------------------
CPUTEventHandledCode CPUTCameraControllerFPS::HandleMouseEvent(
    int x,
    int y,
    int wheel,
    CPUTMouseState state
)
{
    if(state & CPUT_MOUSE_LEFT_DOWN)
    {
        float3 position = mpCamera->GetPosition();

        if(!(mPrevFrameState & CPUT_MOUSE_LEFT_DOWN)) // Mouse was just clicked
        {
            mnPrevFrameX = x;
            mnPrevFrameY = y;
        }

        float nDeltaX = (float)(x-mnPrevFrameX);
        float nDeltaY = (float)(y-mnPrevFrameY);

        float4x4 rotationX = float4x4RotationX(nDeltaY*mfLookSpeed);
        float4x4 rotationY = float4x4RotationY(nDeltaX*mfLookSpeed);

        mpCamera->SetPosition(0.0f, 0.0f, 0.0f); // Rotate about camera center
        float4x4 parent      = *mpCamera->GetParentMatrix();
        float4x4 orientation = rotationX  *parent * rotationY;
        orientation.orthonormalize();
        mpCamera->SetParentMatrix( orientation );
        mpCamera->SetPosition( position.x, position.y, position.z ); // Move back to original position
        mpCamera->Update();

        mnPrevFrameX = x;
        mnPrevFrameY = y;
        mPrevFrameState = state;
        return CPUT_EVENT_HANDLED;
    } else
    {
        mPrevFrameState = state;
        return CPUT_EVENT_UNHANDLED;
    }
}

//-----------------------------------------------------------------------------
CPUTEventHandledCode CPUTCameraControllerArcBall::HandleMouseEvent(
    int x,
    int y,
    int wheel,
    CPUTMouseState state
)
{
    // TODO: We want move-in-x to orbit light in view space, not object space.

    if(state & CPUT_MOUSE_RIGHT_DOWN) // TODO: How to make this flexible?  Want to choose which mouse button has effect.
    {
        float4x4  rotationX, rotationY;

        if(!(mPrevFrameState & CPUT_MOUSE_RIGHT_DOWN)) // Mouse was just clicked
        {
            mnPrevFrameX = x;
            mnPrevFrameY = y;
        }
        int nDeltaX = x-mnPrevFrameX;
        int nDeltaY = y-mnPrevFrameY;

        rotationY = float4x4RotationX(nDeltaY*mfLookSpeed);
        rotationX = float4x4RotationY(nDeltaX*mfLookSpeed);
        float4x4 orientation = *mpCamera->GetParentMatrix() * rotationY * rotationX;

        orientation.orthonormalize();
        mpCamera->SetParentMatrix( orientation );

        mnPrevFrameX = x;
        mnPrevFrameY = y;
        mPrevFrameState = state;
        return CPUT_EVENT_HANDLED;
    } else
    {
        mPrevFrameState = state;
        return CPUT_EVENT_UNHANDLED;
    }
}
