import React from 'react';
import ImageCellView from './imageCell';
import EditableCell from './editableCell';
import DeleteCell from './deleteCell';

const DateCell = data => <p>{data.toLocaleString()}</p>;
const ImageCell = src => <ImageCellView src={src} />;
const LinkCell = (link, href) => <a href={href ? href : '#'}>{link}</a>;
const TextCell = text => <p>{text}</p>;

export { DateCell, ImageCell, LinkCell, TextCell, EditableCell, DeleteCell };
