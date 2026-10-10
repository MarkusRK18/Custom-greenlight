// BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
//
// Copyright (c) 2022 BigBlueButton Inc. and by respective authors (see below).
//
// This program is free software; you can redistribute it and/or modify it under the
// terms of the GNU Lesser General Public License as published by the Free Software
// Foundation; either version 3.0 of the License, or (at your option) any later
// version.
//
// Greenlight is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with Greenlight; if not, see <http://www.gnu.org/licenses/>.

import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../../contexts/auth/AuthProvider';
import Logo from '../shared_components/Logo';

export default function HomePage() {
  const currentUser = useAuth();
  if (currentUser.stateChanging) return null;
  if (!currentUser.signed_in) {
    return (
      <div className="vertical-center text-center">
        <div className="pb-4"><Logo showName={false} /></div>
        <h1 className="mb-3" style={{ color: '#004d00' }}>Welcome to SIETConnect</h1>
        <p className="mb-4" style={{ color: '#004d00' }}>Sri Shakthi Institue of Engineering and Technology</p>
      </div>
    );
  }
  return <Navigate to={currentUser.permissions.CreateRoom === 'true' ? '/rooms' : '/home'} replace />;
}
