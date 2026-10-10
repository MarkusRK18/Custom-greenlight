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

/* eslint-disable react/jsx-props-no-spreading */

import React from 'react';
import {
  Button, Row, Stack, Form,
} from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import PropTypes from 'prop-types';
import { useTranslation } from 'react-i18next';
import useRoom from '../../../../../hooks/queries/rooms/useRoom';
import useUpdateRoom from '../../../../../hooks/mutations/rooms/useUpdateRoom';

export default function UpdateRoomNameForm({ friendlyId }) {
  const { t } = useTranslation();
  const {
    register,
    handleSubmit,
    watch,
  } = useForm();
  const { data: room } = useRoom(friendlyId);
  const updateRoom = useUpdateRoom({ friendlyId });
  const durationMode = watch('duration_mode', room.duration_minutes === 0 ? 'unlimited' : 'limited');

  const updateSchedule = (values) => {
    const updated = { ...values.room, duration_minutes: values.duration_mode === 'unlimited' ? 0 : values.room.duration_minutes };
    updated.scheduled_at = new Date(updated.scheduled_at).toISOString();
    updateRoom.mutate({ room: updated });
  };
  const localStart = room.scheduled_at
    ? new Date(new Date(room.scheduled_at).getTime() - new Date(room.scheduled_at).getTimezoneOffset() * 60000).toISOString().slice(0, 16)
    : '';

  return (
    <Row>
      <h6 className="text-brand">{ t('room.room_name') }</h6>
      <Form onSubmit={handleSubmit(updateSchedule)}>
        <Form.Label htmlFor="scheduled-start">Meeting date and time (your local time)</Form.Label>
        <Form.Control id="scheduled-start" type="datetime-local" defaultValue={localStart} {...register('room.scheduled_at', { required: true })} />
        <Form.Label htmlFor="duration-mode">Duration mode</Form.Label>
        <Form.Select id="duration-mode" defaultValue={room.duration_minutes === 0 ? 'unlimited' : 'limited'} {...register('duration_mode')}>
          <option value="limited">Limited time</option>
          <option value="unlimited">Unlimited time</option>
        </Form.Select>
        {durationMode === 'limited' && <>
        <Form.Label htmlFor="scheduled-duration">Duration (minutes)</Form.Label>
        <Form.Control id="scheduled-duration" type="number" defaultValue={room.duration_minutes || 60} {...register('room.duration_minutes', { required: durationMode === 'limited', min: 1, max: 1440 })} />
        </>}
        <Form.Label htmlFor="scheduled-participants">Participant emails (siet.ac.in only)</Form.Label>
        <Form.Control id="scheduled-participants" type="text" defaultValue={room.participant_emails} {...register('room.participant_emails')} />
        <Stack direction="horizontal">
          <Form.Control type="text" defaultValue={room.name} {...register('room.name', { minLength: 2, maxLength: 255 })} />
          <Button type="submit" variant="brand" className="ms-3"> { t('update') } </Button>
        </Stack>
      </Form>

    </Row>
  );
}

UpdateRoomNameForm.propTypes = {
  friendlyId: PropTypes.string.isRequired,
};
