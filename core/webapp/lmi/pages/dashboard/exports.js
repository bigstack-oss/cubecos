// pages/dashboard/exports.js

import React, { Component } from 'react';
import Page from '../../hocs/securedPage';
import dashboard from '../../app/dashboard';

const Exports = dashboard.containers.Exports;

export default Page(() => <Exports />);
