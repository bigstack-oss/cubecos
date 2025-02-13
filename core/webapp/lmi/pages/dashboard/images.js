// pages/dashboard/images.js

import React, { Component } from 'react';
import Page from '../../hocs/securedPage';
import dashboard from '../../app/dashboard';

const Images = dashboard.containers.Images;

export default Page(() => <Images />);
