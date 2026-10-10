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
import {
  Button, Stack, Form as BootstrapForm,
} from 'react-bootstrap';
import PropTypes from 'prop-types';
import { useTranslation } from 'react-i18next';
import Form from '../../../shared_components/forms/Form';
import Spinner from '../../../shared_components/utilities/Spinner';
import FormControl from '../../../shared_components/forms/FormControl';
import { useAuth } from '../../../../contexts/auth/AuthProvider';
import useRoomForm from '../../../../hooks/forms/rooms/useRoomForm';

export default function CreateRoomForm({ mutation: useCreateRoomAPI, userId, handleClose }) {
  const { t } = useTranslation();
  const currentUser = useAuth();
  const createRoomAPI = useCreateRoomAPI({ onSettled: handleClose, user_id: currentUser.id });
  const { methods, fields } = useRoomForm({ defaultValues: { user_id: userId } });
  const meetingType = methods.watch('meeting_type');
  const createMeeting = (values) => {
    const payload = { ...values };
    if (values.meeting_type === 'scheduled') {
      payload.scheduled_at = new Date(values.scheduled_at).toISOString();
    } else {
      delete payload.scheduled_at;
    }
    createRoomAPI.mutate(payload);
  };

  return (
    <Form methods={methods} onSubmit={createMeeting}>
      <BootstrapForm.Group className="mb-3">
        <BootstrapForm.Label>Meeting type</BootstrapForm.Label>
        <BootstrapForm.Check type="radio" id="instant-meeting" label="Instant meeting" value="instant" {...methods.register('meeting_type')} />
        <BootstrapForm.Check type="radio" id="scheduled-meeting" label="Scheduled meeting" value="scheduled" {...methods.register('meeting_type')} />
        <BootstrapForm.Text>
          {meetingType === 'instant' ? 'Create a meeting you can start now.' : 'Choose when the meeting will be available.'}
        </BootstrapForm.Text>
      </BootstrapForm.Group>
      <FormControl field={fields.name} type="text" />
      {meetingType === 'scheduled' && <FormControl field={fields.scheduled_at} type="datetime-local" />}
      <FormControl field={fields.duration_minutes} type="number" min="1" max="1440" />
      <FormControl field={fields.participant_emails} type="text" />
      <Stack className="mt-1" direction="horizontal" gap={1}>
        <Button variant="neutral" className="ms-auto" onClick={handleClose}>
          { t('close') }
        </Button>
        <Button variant="brand" type="submit" disabled={createRoomAPI.isLoading}>
          {createRoomAPI.isLoading && <Spinner className="me-2" />}
          {meetingType === 'instant' ? 'Create instant meeting' : 'Schedule meeting'}
        </Button>
      </Stack>
    </Form>
  );
}

CreateRoomForm.propTypes = {
  handleClose: PropTypes.func,
  mutation: PropTypes.func.isRequired,
  userId: PropTypes.string.isRequired,
};

CreateRoomForm.defaultProps = {
  handleClose: () => { },
};
