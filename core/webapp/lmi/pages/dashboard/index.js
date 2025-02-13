// pages/dashboard/index.js

import React, { Component } from 'react';
import Link from 'next/link';
import Page from '../../hocs/securedPage';
import dashboard from '../../app/dashboard';

const Dashboard = dashboard.containers.Dashboard;

export default Page(() => <Dashboard />);
