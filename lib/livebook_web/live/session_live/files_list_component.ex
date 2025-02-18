defmodule LivebookWeb.SessionLive.FilesListComponent do
  use LivebookWeb, :live_component

  alias Livebook.FileSystem

  @impl true
  def update(%{transfer_file_entry_result: file_entry_result}, socket) do
    case file_entry_result do
      {:ok, file_entry} ->
        Livebook.Session.add_file_entries(socket.assigns.session.pid, [file_entry])

      {:error, message} ->
        send(self(), {:put_flash, :error, Livebook.Utils.upcase_first(message)})
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col grow">
      <div class="flex justify-between items-center">
        <h3 class="uppercase text-sm font-semibold text-gray-500">
          Files
        </h3>
        <.files_info_icon />
      </div>
      <div class="mt-5 flex flex-col gap-1">
        <div :for={{file_entry, idx} <- Enum.with_index(@file_entries)} class="flex justify-between">
          <div class="flex items-center text-gray-500">
            <.remix_icon icon={file_entry_icon(file_entry.type)} class="text-lg align-middle mr-2" />
            <span><%= file_entry.name %></span>
          </div>
          <.menu id={"file-entry-#{idx}-menu"} position={:bottom_right}>
            <:toggle>
              <button class="icon-button" aria-label="menu">
                <.remix_icon icon="more-2-line" />
              </button>
            </:toggle>
            <.menu_item>
              <button
                :if={file_entry.type != :attachment}
                role="menuitem"
                phx-click={
                  JS.push("transfer_file_entry", value: %{name: file_entry.name}, target: @myself)
                }
              >
                <.remix_icon icon="file-transfer-line" />
                <span>Copy to files</span>
              </button>
            </.menu_item>
            <.menu_item disabled={not Livebook.Session.file_entry_cacheable?(@session, file_entry)}>
              <button
                role="menuitem"
                phx-click={
                  JS.push("clear_file_entry_cache",
                    value: %{name: file_entry.name},
                    target: @myself
                  )
                }
              >
                <.remix_icon icon="eraser-line" />
                <span>Clear cache</span>
              </button>
            </.menu_item>
            <.menu_item variant={:danger}>
              <button
                role="menuitem"
                phx-click={
                  JS.push("delete_file_entry", value: %{name: file_entry.name}, target: @myself)
                }
              >
                <.remix_icon icon="delete-bin-line" />
                <span>Delete</span>
              </button>
            </.menu_item>
          </.menu>
        </div>
      </div>
      <div class="flex mt-5">
        <.link
          class="w-full flex items-center justify-center p-8 py-1 space-x-2 text-sm font-medium text-gray-500 border border-gray-400 border-dashed rounded-xl hover:bg-gray-100"
          role="button"
          patch={~p"/sessions/#{@session.id}/add-file/file"}
        >
          <.remix_icon icon="add-line" class="text-lg align-center" />
          <span>New file</span>
        </.link>
      </div>
    </div>
    """
  end

  defp files_info_icon(assigns) do
    ~H"""
    <span
      class="icon-button p-0 cursor-pointer tooltip bottom-left"
      data-tooltip={
        ~S'''
        Manage files used by the notebook.
        Files are either links to existing
        resources or hard copies stored in
        the notebook files directory.
        '''
      }
    >
      <.remix_icon icon="question-line" class="text-xl leading-none" />
    </span>
    """
  end

  defp file_entry_icon(:attachment), do: "file-3-line"
  defp file_entry_icon(:file), do: "share-forward-line"
  defp file_entry_icon(:url), do: "global-line"

  @impl true
  def handle_event("delete_file_entry", %{"name" => name}, socket) do
    if file_entry = find_file_entry(socket, name) do
      session = socket.assigns.session

      on_confirm = fn socket, options ->
        Livebook.Session.delete_file_entry(session.pid, file_entry.name)

        if Map.get(options, "delete_from_file_system", false) do
          file = FileSystem.File.resolve(session.files_dir, file_entry.name)

          case FileSystem.File.remove(file) do
            :ok ->
              socket

            {:error, error} ->
              put_flash(socket, :error, "Failed to remove #{file.path}, reason: #{error}")
          end
        else
          socket
        end
      end

      assigns = %{name: file_entry.name}

      description = ~H"""
      Are you sure you want to delete this file - <span class="font-semibold">“<%= @name %>”</span>?
      """

      {:noreply,
       confirm(socket, on_confirm,
         title: "Delete file",
         description: description,
         confirm_text: "Delete",
         confirm_icon: "delete-bin-6-line",
         options:
           if file_entry.type == :attachment do
             [
               %{
                 name: "delete_from_file_system",
                 label: "Delete the corresponding file from the file system",
                 default: true,
                 disabled: false
               }
             ]
           else
             []
           end
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("transfer_file_entry", %{"name" => name}, socket) do
    if file_entry = find_file_entry(socket, name) do
      pid = self()
      id = socket.assigns.id
      session = socket.assigns.session

      Task.Supervisor.async_nolink(Livebook.TaskSupervisor, fn ->
        file_entry_result = Livebook.Session.to_attachment_file_entry(session, file_entry)
        send_update(pid, __MODULE__, id: id, transfer_file_entry_result: file_entry_result)
      end)
    end

    {:noreply, socket}
  end

  def handle_event("clear_file_entry_cache", %{"name" => name}, socket) do
    if file_entry = find_file_entry(socket, name) do
      Livebook.Session.clear_file_entry_cache(socket.assigns.session.id, file_entry.name)
    end

    {:noreply, socket}
  end

  defp find_file_entry(socket, name) do
    Enum.find(socket.assigns.file_entries, &(&1.name == name))
  end
end
