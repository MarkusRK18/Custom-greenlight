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

import * as yup from 'yup';
import { yupResolver } from '@hookform/resolvers/yup';
import { useTranslation } from 'react-i18next';
import { useForm } from 'react-hook-form';
import { useCallback, useMemo } from 'react';

export function useRoomFormValidation() {
  return useMemo(() => (yup.object({
    meeting_type: yup.string().oneOf(['instant', 'scheduled']).required(),
    scheduled_at: yup.string().when('meeting_type', {
      is: 'scheduled',
      then: (schema) => schema.required('Choose a meeting date and time'),
    }),
    duration_mode: yup.string().oneOf(['limited', 'unlimited']).required(),
    duration_minutes: yup.number().when('duration_mode', {
      is: 'limited', then: (schema) => schema.integer().min(1).max(1440).required(),
      otherwise: (schema) => schema.notRequired(),
    }),
    participant_emails: yup.string(),
    name: yup.string().required('forms.validations.room.name.required').min(2, 'forms.validations.room.name.min'),
  })), []);
}

export default function useRoomForm({ defaultValues: _defaultValues, ..._config } = {}) {
  const { t, i18n } = useTranslation();

  const fields = useMemo(() => ({
    scheduled_at: { label: 'Meeting date and time (your local time)', controlId: 'meetingStart', hookForm: { id: 'scheduled_at' } },
    duration_minutes: { label: 'Duration (minutes)', controlId: 'meetingDuration', hookForm: { id: 'duration_minutes' } },
    participant_emails: { label: 'Participant emails (comma separated, siet.ac.in only)', controlId: 'meetingParticipants', hookForm: { id: 'participant_emails' } },
    name: {
      label: t('forms.room.fields.name.label'),
      placeHolder: t('forms.room.fields.name.placeholder'),
      controlId: 'createRoleFormName',
      hookForm: {
        id: 'name',
      },
    },
  }), [i18n.resolvedLanguage]);

  const validationSchema = useRoomFormValidation();

  const config = useMemo(() => ({
    ...{
      mode: 'onChange',
      defaultValues: {
        ...{
          name: '',
          meeting_type: 'instant',
          scheduled_at: '',
          duration_mode: 'limited',
          duration_minutes: 60,
          participant_emails: '',
          user_id: '',
        },
        ..._defaultValues,
      },
      resolver: yupResolver(validationSchema),
    },
    ..._config,
  }), [validationSchema, _defaultValues]);

  const methods = useForm(config);

  const reset = useCallback(() => methods.reset(config.defaultValues), [methods.reset, config.defaultValues]);

  return { methods, fields, reset };
}
