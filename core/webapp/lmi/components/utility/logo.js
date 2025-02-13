import React from 'react';
import Link from 'next/link';
import { siteConfig } from '../../config';
const logo = '/static/image/cube_logo_white.png';
const icon = '/static/image/cube_icon.png';
import { LogoWrapper } from './logo.style';

export default function({ collapsed }) {
	return (
		<LogoWrapper className="isoLogoWrapper" style={{display: 'flex', paddingLeft: '24px'}}>
			{collapsed ? (
				<h3><img src={icon} alt={siteConfig.siteName}/></h3>
			) : (
				<h3><img src={logo} alt={siteConfig.siteName}/></h3>
			)}
		</LogoWrapper>
	);
}
