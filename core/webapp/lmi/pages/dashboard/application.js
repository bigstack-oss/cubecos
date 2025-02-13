// pages/dashboard/app.js

import React, { Component } from 'react';
import Link from 'next/link';
import Page from '../../hocs/securedPage';
import dashboard from '../../app/dashboard';

const Application = dashboard.containers.Application;

export default Page(() => <Application />);
