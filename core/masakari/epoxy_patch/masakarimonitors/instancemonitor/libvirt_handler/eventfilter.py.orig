# Copyright(c) 2016 Nippon Telegraph and Telephone Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import socket
import sys
import threading

from oslo_log import log as oslo_logging
from oslo_utils import excutils
from oslo_utils import timeutils

import masakarimonitors.conf
from masakarimonitors.instancemonitor.libvirt_handler import callback
from masakarimonitors.instancemonitor.libvirt_handler \
    import eventfilter_table as evft
from masakarimonitors.objects import event_constants as ec


LOG = oslo_logging.getLogger(__name__)
CONF = masakarimonitors.conf.CONF


class EventFilter(object):
    """Class of filtering events."""

    def __init__(self):
        self.callback = callback.Callback()

    def vir_event_filter(self, eventID, eventType, detail, uuID):
        """Filter events from libvirt.

        :param eventID: EventID
        :param eventType: Event type
        :param detail: Event name
        :pram uuID: UUID
        """

        noticeType = ec.EventConstants.TYPE_VM
        hostname = CONF.hostname or socket.gethostname()
        currentTime = timeutils.utcnow()

        # All Event Output if debug mode is on.
        msg = "libvirt Event Received.type = %s \
            hostname = %s uuid = %s time = %s eventID = %d eventType = %d \
            detail = %d" % (
            noticeType,
            hostname, uuID, currentTime, eventID,
            eventType, detail)
        LOG.debug(msg)

        try:
            if detail in evft.event_filter_dic[eventID][eventType]:
                LOG.debug("Event Filter Matched.")

                eventID_val = evft.eventID_dic[eventID]
                detail_val = evft.detail_dic[eventID][eventType][detail]

                # callback Thread Start
                thread = threading.Thread(
                    target=self.callback.libvirt_event_callback,
                    args=(eventID_val, detail_val,
                          uuID, noticeType,
                          hostname, currentTime)
                )
                thread.start()
            else:
                LOG.debug("Event Filter Unmatched.")

        except KeyError:
            LOG.debug("virEventFilter KeyError")
        except IndexError:
            LOG.debug("virEventFilter IndexError")
        except TypeError:
            LOG.debug("virEventFilter TypeError")
        except Exception:
            with excutils.save_and_reraise_exception():
                LOG.debug("Unexpected error: %s" % sys.exc_info()[0])
