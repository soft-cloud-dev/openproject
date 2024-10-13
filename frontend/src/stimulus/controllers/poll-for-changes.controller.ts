/*
 * -- copyright
 * OpenProject is an open source project management software.
 * Copyright (C) 2023 the OpenProject GmbH
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 3.
 *
 * OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
 * Copyright (C) 2006-2013 Jean-Philippe Lang
 * Copyright (C) 2010-2013 the ChiliProject Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * See COPYRIGHT and LICENSE files for more details.
 * ++
 */

import { ApplicationController } from 'stimulus-use';
import { renderStreamMessage } from '@hotwired/turbo';

export default class PollForChangesController extends ApplicationController {
  static values = {
    url: String,
    interval: Number,
    reference: String,
    autoscrollEnabled: Boolean,
  };

  static targets = ['reloadButton', 'reference'];

  declare reloadButtonTarget:HTMLLinkElement;
  declare referenceTarget:HTMLElement;
  declare readonly hasReferenceTarget:boolean;

  declare referenceValue:string;
  declare urlValue:string;
  declare intervalValue:number;
  declare autoscrollEnabledValue:boolean;

  private interval:number;

  connect() {
    super.connect();

    if (this.intervalValue !== 0) {
      this.interval = setInterval(() => {
        void this.triggerTurboStream();
      }, this.intervalValue || 10_000);
    }

    if (this.autoscrollEnabledValue) {
      window.addEventListener('DOMContentLoaded', this.autoscrollToLastKnownPosition.bind(this));
    }
  }

  disconnect() {
    super.disconnect();
    clearInterval(this.interval);
  }

  buildReference():string {
    if (this.hasReferenceTarget) {
      return this.referenceTarget.dataset.referenceValue as string;
    }

    return this.referenceValue;
  }

  reloadButtonTargetConnected() {
    this.reloadButtonTarget.addEventListener('click', this.rememberCurrentScrollPosition.bind(this));
  }

  triggerTurboStream() {
    void fetch(`${this.urlValue}?reference=${this.buildReference()}`, {
      headers: {
        Accept: 'text/vnd.turbo-stream.html',
      },
    }).then(async (r) => {
      if (r.status === 200) {
        clearInterval(this.interval);

        const html = await r.text();
        renderStreamMessage(html);
      }
    });
  }

  rememberCurrentScrollPosition() {
    const currentPosition = document.getElementById('content-body')?.scrollTop;

    if (currentPosition !== undefined) {
      sessionStorage.setItem(this.scrollPositionKey(), currentPosition.toString());
    }
  }

  autoscrollToLastKnownPosition() {
    const lastKnownPos = sessionStorage.getItem(this.scrollPositionKey());
    if (lastKnownPos) {
      const content = document.getElementById('content-body');

      if (content) {
        content.scrollTop = parseInt(lastKnownPos, 10);
      }
    }

    sessionStorage.removeItem(this.scrollPositionKey());
  }

  private scrollPositionKey():string {
    return `${this.urlValue}/scrollPosition`;
  }
}
