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
import {
  ComputerDesktopIcon, VideoCameraIcon, Cog6ToothIcon, WrenchScrewdriverIcon,
} from '@heroicons/react/24/outline';
import { useAuth } from '../../contexts/auth/AuthProvider';
import HomepageFeatureCard from './HomepageFeatureCard';

export default function HomePage() {
  const currentUser = useAuth();
  if (currentUser.stateChanging) return null;
  if (!currentUser.signed_in) {
    return (
      <main className="homepage">
        <section className="homepage-hero-band">
          <div className="homepage-content" id="homepage-hero">
            <h1>Welcome to SIETConnect.</h1>
            <p>
              SIETConnect is the online classroom and meeting space for Sri Shakthi Institute of
              Engineering and Technology. Collaborate, share ideas, and learn together in real time.
            </p>
            <p>Create your own rooms to host sessions, or join others using a short and convenient link.</p>
          </div>
        </section>
        <section className="homepage-features-band" aria-labelledby="homepage-features-title">
          <div className="homepage-content">
            <h2 id="homepage-features-title">EXPLORE OUR FEATURES</h2>
            <div className="homepage-feature-grid">
              <HomepageFeatureCard
                title="Launch a meeting"
                description="Start a virtual class with video, audio, screen sharing, chat, and tools for learning together."
                icon={<ComputerDesktopIcon aria-hidden="true" />}
              />
              <HomepageFeatureCard
                title="Record your meetings"
                description="Record SIETConnect meetings and share them with students to review after class."
                icon={<VideoCameraIcon aria-hidden="true" />}
              />
              <HomepageFeatureCard
                title="Manage your rooms"
                description="Configure your rooms and meeting settings to create an effective classroom."
                icon={<Cog6ToothIcon aria-hidden="true" />}
              />
              <HomepageFeatureCard
                title="And more!"
                description="Use built-in learning tools designed to help you make the most of every session."
                icon={<WrenchScrewdriverIcon aria-hidden="true" />}
              />
            </div>
          </div>
        </section>
      </main>
    );
  }
  return <Navigate to={currentUser.permissions.CreateRoom === 'true' ? '/rooms' : '/home'} replace />;
}
